import Foundation
import Observation
import OSLog

/// Outbox-based sync. Records are written locally first (source of truth while
/// offline); the engine flushes non-synced records to the backend when online.
///
/// Flow per run:
///   1. upload each pending photo (signed URL → PUT to Storage)
///   2. POST /sync the records in batches (≤100, the backend's limit)
///   3. mark each record synced/failed from the per-item response
/// Client UUIDs make every step safe to retry. Failures back off 2s → 32s, and
/// a reconnect or the "Sync now" button retries immediately.
@MainActor
@Observable
final class SyncEngine {
    enum Status: Equatable {
        case idle
        case syncing
        case offline
        case notConfigured
        case signedOut
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var pendingCount = 0
    private(set) var lastSyncedAt: Date?
    private(set) var catalogRefreshedAt: Date?
    private(set) var catalogError: String?

    @ObservationIgnored private let api: LabLogAPI?
    @ObservationIgnored private let store: LocalStore
    @ObservationIgnored private let isOnline: () -> Bool
    @ObservationIgnored private let isSignedIn: () -> Bool
    @ObservationIgnored private let readPhoto: (String) throws -> Data
    @ObservationIgnored private let downloadPhoto: (URL) async throws -> Data
    @ObservationIgnored private let savePhoto: (Data, UUID) throws -> String
    @ObservationIgnored private let constraints = StepConstraintEngine()
    @ObservationIgnored private let logger = Logger(subsystem: "com.thxnura.LabLog", category: "sync")
    @ObservationIgnored private var isRunning = false
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryAttempt = 0

    static let batchSize = 100
    static let maxRetries = 5

    /// `api` is nil when the build has no backend configured.
    init(api: LabLogAPI?,
         store: LocalStore,
         isOnline: @escaping () -> Bool,
         isSignedIn: @escaping () -> Bool,
         readPhoto: @escaping (String) throws -> Data = EvidenceStore.data(for:),
         downloadPhoto: @escaping (URL) async throws -> Data = SyncEngine.download,
         savePhoto: @escaping (Data, UUID) throws -> String = EvidenceStore.save(data:id:)) {
        self.api = api
        self.store = store
        self.isOnline = isOnline
        self.isSignedIn = isSignedIn
        self.readPhoto = readPhoto
        self.downloadPhoto = downloadPhoto
        self.savePhoto = savePhoto
        refreshPendingCount()
    }

    func refreshPendingCount() {
        pendingCount = store.pendingRecords().count
    }

    /// Flush the outbox. Safe to call repeatedly; overlapping calls are dropped.
    func sync() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        refreshPendingCount()
        guard let api else { status = .notConfigured; return }
        guard isOnline() else { status = .offline; return }
        guard isSignedIn() else { status = .signedOut; return }

        let pending = store.pendingRecords()
        guard !pending.isEmpty else {
            status = .idle
            return
        }
        status = .syncing
        var firstError: String?

        // 1. Photos first — a record is only pushed once all its photos are in Storage.
        var ready: [LabRecord] = []
        for record in pending {
            do {
                try await uploadPhotos(of: record, api: api)
                ready.append(record)
            } catch {
                let message = "Photo upload failed: \(error.localizedDescription)"
                store.applySyncResult(id: record.id, synced: false, sentRevision: record.revision, error: message)
                firstError = firstError ?? message
            }
        }

        // 2 + 3. Push in batches and reconcile per item.
        for start in stride(from: 0, to: ready.count, by: Self.batchSize) {
            let batch = Array(ready[start..<min(start + Self.batchSize, ready.count)])
            let revisions = Dictionary(batch.map { ($0.id, $0.revision) }, uniquingKeysWith: { first, _ in first })
            do {
                let response = try await api.sync(SyncRequestDTO(records: batch.map(store.makeDTO)))
                for result in response.results {
                    let synced = result.status == "synced"
                    store.applySyncResult(id: result.id, synced: synced,
                                          sentRevision: revisions[result.id] ?? -1, error: result.error)
                    if !synced { firstError = firstError ?? (result.error ?? "Record rejected by server") }
                }
            } catch {
                for record in batch {
                    store.applySyncResult(id: record.id, synced: false, sentRevision: record.revision,
                                          error: error.localizedDescription)
                }
                firstError = firstError ?? error.localizedDescription
            }
        }

        refreshPendingCount()
        if let firstError {
            logger.error("Sync failed: \(firstError, privacy: .public)")
            status = .failed(firstError)
            scheduleRetry()
        } else {
            status = .idle
            lastSyncedAt = Date()
            retryAttempt = 0
            // Edits made mid-sync stay pending; pick them up straight away.
            if pendingCount > 0 { scheduleRetry(after: 1) }
        }
    }

    /// Restores the student's own records from the server: after signing in on
    /// a new phone, or after signing out cleared this one (ADR-028). Records
    /// already on the phone win, so nothing local is overwritten. Their photos
    /// are downloaded, so the evidence can be viewed offline too.
    func pullRecords() async {
        guard let api, isOnline(), isSignedIn() else { return }
        do {
            let downloads = store.restore(try await api.myRecords())
            for photo in downloads {
                do {
                    let fileName = try savePhoto(try await downloadPhoto(photo.url), photo.attachmentId)
                    store.setAttachmentFile(id: photo.attachmentId, fileName: fileName)
                } catch {
                    logger.error("Photo download failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            refreshPendingCount()
        } catch {
            logger.error("Restoring records failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Downloads a signed photo URL, treating any non-2xx answer as an error.
    nonisolated static func download(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else { throw APIError.badStatus(status, nil) }
        return data
    }

    /// Pulls the server catalog and caches it. Experiments whose step graph
    /// fails validation (cycle / dangling prerequisite) are skipped.
    func refreshCatalog() async {
        guard let api, isOnline(), isSignedIn() else { return }
        do {
            var experiments: [Experiment] = []
            var steps: [Step] = []
            let labs = try await api.labs()
            // One request per lab, then one per experiment: run each round
            // concurrently instead of one after another (the catalog grows as
            // lecturers add experiments, ADR-029).
            let listed = try await withThrowingTaskGroup(of: [Experiment].self) { group in
                for lab in labs { group.addTask { @MainActor in try await api.experiments(labId: lab.id) } }
                return try await group.reduce(into: []) { $0 += $1 }
            }
            let details = try await withThrowingTaskGroup(of: ExperimentDetailDTO.self) { group in
                for experiment in listed { group.addTask { @MainActor in try await api.experimentDetail(id: experiment.id) } }
                return try await group.reduce(into: []) { $0.append($1) }
            }
            for detail in details {
                let issues = constraints.validate(detail.steps)
                guard issues.isEmpty else {
                    logger.error("Skipping \(detail.title, privacy: .public): invalid step graph \(String(describing: issues), privacy: .public)")
                    continue
                }
                experiments.append(detail.experiment)
                steps += detail.steps
            }
            store.replaceCatalog(labs: labs, experiments: experiments, steps: steps)
            // The server's list is this account's catalog: a lecturer's view or
            // the labs another student was enrolled in don't stay on the phone.
            store.keepOnlyLabs(Set(labs.map(\.id)))
            catalogRefreshedAt = Date()
            catalogError = nil
        } catch {
            catalogError = error.localizedDescription
            logger.error("Catalog refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Private

    private func uploadPhotos(of record: LabRecord, api: LabLogAPI) async throws {
        for attachment in store.pendingAttachments(recordId: record.id) {
            guard let fileName = attachment.localPath else { continue }
            let data: Data
            do {
                data = try readPhoto(fileName)
            } catch {
                // The file is gone; uploading can never succeed. Drop it rather
                // than block the whole record forever.
                store.markAttachmentLost(attachment.id)
                continue
            }
            let signed = try await api.signUpload(recordId: record.id, attachmentId: attachment.id)
            try await api.uploadPhoto(data, to: signed)
            store.markAttachmentUploaded(attachment.id, storagePath: signed.storagePath)
        }
    }

    private func scheduleRetry(after seconds: Double? = nil) {
        retryTask?.cancel()
        let delay: Double
        if let seconds {
            delay = seconds
        } else {
            retryAttempt += 1
            guard retryAttempt <= Self.maxRetries else { return }
            delay = pow(2, Double(retryAttempt)) // 2, 4, 8, 16, 32 s
        }
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }
}

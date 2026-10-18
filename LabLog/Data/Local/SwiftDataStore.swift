import Foundation
import Observation
import OSLog
import SwiftData

/// SwiftData-backed `LocalStore`. The on-device source of truth: the UI reads
/// and writes here, and the SyncEngine drains its outbox (non-synced records).
@MainActor
@Observable
final class SwiftDataStore: LocalStore {
    private(set) var version = 0

    /// Held strongly: a ModelContext does not keep its container alive, and
    /// using the context after the container is freed traps inside SwiftData.
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let logger = Logger(subsystem: "com.thxnura.LabLog", category: "store")

    init(container: ModelContainer) {
        self.container = container
        context = container.mainContext
    }

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema([
            LabEntity.self, ExperimentEntity.self, StepEntity.self,
            RecordEntity.self, StepCompletionEntity.self, ObservationEntity.self, AttachmentEntity.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // MARK: Catalog

    func hasCatalog() -> Bool {
        ((try? context.fetchCount(FetchDescriptor<LabEntity>())) ?? 0) > 0
    }

    func replaceCatalog(labs: [Lab], experiments: [Experiment], steps: [Step]) {
        for lab in labs {
            if let existing = labEntity(lab.id) {
                existing.name = lab.name
                existing.code = lab.code
            } else {
                context.insert(LabEntity(lab))
            }
        }
        for experiment in experiments {
            if let existing = experimentEntity(experiment.id) {
                existing.labId = experiment.labId
                existing.title = experiment.title
                existing.summary = experiment.description
            } else {
                context.insert(ExperimentEntity(experiment))
            }
            // The server owns the step graph: replace it wholesale per experiment.
            let experimentId = experiment.id
            for old in fetch(FetchDescriptor<StepEntity>(predicate: #Predicate { $0.experimentId == experimentId })) {
                context.delete(old)
            }
        }
        for step in steps {
            context.insert(StepEntity(step))
        }
        save()
    }

    func keepOnlyLabs(_ ids: Set<UUID>) {
        for lab in fetch(FetchDescriptor<LabEntity>()) where !ids.contains(lab.id) {
            let labId = lab.id
            for experiment in fetch(FetchDescriptor<ExperimentEntity>(predicate: #Predicate { $0.labId == labId })) {
                let experimentId = experiment.id
                for step in fetch(FetchDescriptor<StepEntity>(predicate: #Predicate { $0.experimentId == experimentId })) {
                    context.delete(step)
                }
                context.delete(experiment)
            }
            context.delete(lab)
        }
        save()
    }

    func labs() -> [Lab] {
        fetch(FetchDescriptor<LabEntity>(sortBy: [SortDescriptor(\.name)])).map(\.domain)
    }

    func experiments(labId: UUID) -> [Experiment] {
        let descriptor = FetchDescriptor<ExperimentEntity>(
            predicate: #Predicate { $0.labId == labId },
            sortBy: [SortDescriptor(\.title)],
        )
        return fetch(descriptor).map(\.domain)
    }

    func experiment(id: UUID) -> Experiment? {
        experimentEntity(id)?.domain
    }

    func steps(experimentId: UUID) -> [Step] {
        let descriptor = FetchDescriptor<StepEntity>(
            predicate: #Predicate { $0.experimentId == experimentId },
            sortBy: [SortDescriptor(\.position)],
        )
        return fetch(descriptor).map(\.domain)
    }

    // MARK: Records

    func createRecord(experimentId: UUID) -> LabRecord {
        // Client-generated UUID: the idempotency key for every future sync.
        let entity = RecordEntity(id: UUID(), experimentId: experimentId, createdAt: Date())
        context.insert(entity)
        save()
        return entity.domain
    }

    /// Discarded drafts (tombstones) are hidden everywhere except the outbox.
    func record(id: UUID) -> LabRecord? {
        guard let entity = recordEntity(id), entity.deletedAt == nil else { return nil }
        return entity.domain
    }

    func records() -> [LabRecord] {
        let descriptor = FetchDescriptor<RecordEntity>(
            predicate: #Predicate { $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)],
        )
        return fetch(descriptor).map(\.domain)
    }

    func records(experimentId: UUID) -> [LabRecord] {
        let descriptor = FetchDescriptor<RecordEntity>(
            predicate: #Predicate { $0.experimentId == experimentId && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)],
        )
        return fetch(descriptor).map(\.domain)
    }

    func completions(recordId: UUID) -> [StepCompletion] {
        let descriptor = FetchDescriptor<StepCompletionEntity>(
            predicate: #Predicate { $0.recordId == recordId },
            sortBy: [SortDescriptor(\.completedAt)],
        )
        return fetch(descriptor).map(\.domain)
    }

    func observation(recordId: UUID) -> LabObservation? {
        observationEntity(recordId: recordId)?.domain
    }

    func attachments(recordId: UUID) -> [Attachment] {
        let descriptor = FetchDescriptor<AttachmentEntity>(
            predicate: #Predicate { $0.recordId == recordId },
            sortBy: [SortDescriptor(\.createdAt)],
        )
        return fetch(descriptor).map(\.domain)
    }

    func addCompletion(_ completion: StepCompletion) {
        let recordId = completion.recordId, stepId = completion.stepId
        let duplicate = FetchDescriptor<StepCompletionEntity>(
            predicate: #Predicate { $0.recordId == recordId && $0.stepId == stepId },
        )
        guard ((try? context.fetchCount(duplicate)) ?? 0) == 0 else { return }
        context.insert(StepCompletionEntity(completion))
        touch(completion.recordId)
        save()
    }

    func setCompletionNote(id: UUID, note: String?) {
        guard let entity = completionEntity(id), isDraft(entity.recordId) else { return }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty ?? true) ? nil : trimmed
        guard entity.note != value else { return }
        entity.note = value
        touch(entity.recordId)
        save()
    }

    func setObservation(recordId: UUID, text: String) {
        if let existing = observationEntity(recordId: recordId) {
            guard existing.text != text else { return }
            existing.text = text
        } else {
            guard !text.isEmpty else { return }
            context.insert(ObservationEntity(id: UUID(), recordId: recordId, text: text))
        }
        touch(recordId)
        save()
    }

    func addAttachment(_ attachment: Attachment) {
        context.insert(AttachmentEntity(attachment, createdAt: Date()))
        touch(attachment.recordId)
        save()
    }

    func removeAttachment(id: UUID) {
        guard let entity = attachmentEntity(id), isDraft(entity.recordId) else { return }
        let recordId = entity.recordId
        if let file = entity.localFileName { EvidenceStore.delete(file) }
        context.delete(entity)
        touch(recordId)
        save()
    }

    func discardDraft(id: UUID, sendTombstone: Bool) {
        guard let entity = recordEntity(id), entity.status == .draft, entity.deletedAt == nil else { return }
        // Never sent → the server can't have it; nothing to tell it.
        guard sendTombstone, entity.syncState != .pendingCreate else {
            purge(entity)
            save()
            return
        }
        deleteChildren(of: id)
        entity.deletedAt = Date()
        entity.revision += 1
        entity.syncState = .pendingUpdate
        entity.lastSyncError = nil
        save()
    }

    func restore(_ records: [SubmissionDTO]) -> [(attachmentId: UUID, url: URL)] {
        var downloads: [(attachmentId: UUID, url: URL)] = []
        for remote in records {
            if recordEntity(remote.id) == nil {
                let entity = RecordEntity(id: remote.id, experimentId: remote.experimentId, createdAt: remote.createdAt)
                entity.status = RecordStatus(rawValue: remote.status) ?? .draft
                entity.latitude = remote.latitude
                entity.longitude = remote.longitude
                entity.submittedAt = remote.submittedAt
                entity.syncState = .synced
                context.insert(entity)
                for c in remote.stepCompletions {
                    context.insert(StepCompletionEntity(StepCompletion(id: c.id, recordId: remote.id, stepId: c.stepId,
                                                                       completedAt: c.completedAt, note: c.note)))
                }
                for o in remote.observations {
                    context.insert(ObservationEntity(id: o.id, recordId: remote.id, text: o.text))
                }
                for photo in remote.attachments {
                    let attachment = Attachment(id: photo.id, recordId: remote.id, stepId: photo.stepId, localPath: nil,
                                                storagePath: photo.storagePath, syncState: .synced)
                    context.insert(AttachmentEntity(attachment, createdAt: remote.submittedAt ?? remote.createdAt))
                    if let url = photo.url { downloads.append((photo.id, url)) }
                }
            } else {
                // Already here: only fetch a photo whose file is missing.
                for photo in remote.attachments {
                    if let url = photo.url, let entity = attachmentEntity(photo.id), entity.localFileName == nil {
                        downloads.append((photo.id, url))
                    }
                }
            }
        }
        save()
        return downloads
    }

    func setAttachmentFile(id: UUID, fileName: String) {
        guard let entity = attachmentEntity(id) else { return }
        entity.localFileName = fileName
        save()
    }

    func removeAllRecords() {
        for entity in fetch(FetchDescriptor<RecordEntity>()) { purge(entity) }
        save()
    }

    func submitRecord(id: UUID, latitude: Double?, longitude: Double?) {
        guard let entity = recordEntity(id), entity.status == .draft else { return }
        entity.status = .submitted
        entity.submittedAt = Date()
        entity.latitude = latitude
        entity.longitude = longitude
        touch(id)
        save()
    }

    // MARK: Outbox

    func pendingRecords() -> [LabRecord] {
        let synced = SyncState.synced.rawValue
        let descriptor = FetchDescriptor<RecordEntity>(
            predicate: #Predicate { $0.syncStateRaw != synced },
            sortBy: [SortDescriptor(\.createdAt)],
        )
        return fetch(descriptor).map(\.domain)
    }

    func pendingAttachments(recordId: UUID) -> [Attachment] {
        attachments(recordId: recordId).filter { $0.syncState != .synced && $0.localPath != nil }
    }

    func makeDTO(_ record: LabRecord) -> SyncRecordDTO {
        if record.deletedAt != nil {
            return SyncRecordDTO(id: record.id, experimentId: record.experimentId, status: record.status.rawValue,
                                 latitude: nil, longitude: nil, createdAt: record.createdAt, submittedAt: nil,
                                 stepCompletions: [], observations: [], attachments: [], deleted: true)
        }
        var observations: [SyncObservationDTO] = []
        if let note = observation(recordId: record.id),
           !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            observations.append(SyncObservationDTO(id: note.id, text: note.text))
        }
        return SyncRecordDTO(
            id: record.id,
            experimentId: record.experimentId,
            status: record.status.rawValue,
            latitude: record.latitude,
            longitude: record.longitude,
            createdAt: record.createdAt,
            submittedAt: record.submittedAt,
            stepCompletions: completions(recordId: record.id).map {
                SyncStepCompletionDTO(id: $0.id, stepId: $0.stepId, completedAt: $0.completedAt, note: $0.note)
            },
            observations: observations,
            // Only photos already in Storage; the rest follow on the next sync.
            attachments: attachments(recordId: record.id).compactMap { attachment in
                attachment.storagePath.map { SyncAttachmentDTO(id: attachment.id, stepId: attachment.stepId, storagePath: $0) }
            },
        )
    }

    // MARK: Sync reconciliation

    func markAttachmentUploaded(_ id: UUID, storagePath: String) {
        guard let entity = attachmentEntity(id) else { return }
        entity.storagePath = storagePath
        entity.syncStateRaw = SyncState.synced.rawValue
        save()
    }

    func markAttachmentLost(_ id: UUID) {
        guard let entity = attachmentEntity(id) else { return }
        entity.localFileName = nil
        entity.syncStateRaw = SyncState.failed.rawValue
        save()
    }

    func applySyncResult(id: UUID, synced: Bool, sentRevision: Int, error: String?) {
        guard let entity = recordEntity(id) else { return }
        if synced, entity.deletedAt != nil {
            // The server has deleted it too; the tombstone has done its job.
            purge(entity)
            save()
            return
        }
        if synced {
            // Edited while the request was in flight → keep it in the outbox.
            entity.syncState = entity.revision == sentRevision ? .synced : .pendingUpdate
            entity.lastSyncError = nil
        } else {
            entity.syncState = .failed
            entity.lastSyncError = error ?? "Sync failed"
        }
        save()
    }

    // MARK: Helpers

    /// Records a local edit: bump the revision and re-queue a synced record.
    private func touch(_ recordId: UUID) {
        guard let entity = recordEntity(recordId) else { return }
        entity.revision += 1
        if entity.syncState == .synced {
            entity.syncState = .pendingUpdate
        }
    }

    private func isDraft(_ recordId: UUID) -> Bool {
        recordEntity(recordId)?.status == .draft
    }

    /// Completions, observation and photos (with their files) of a record.
    private func deleteChildren(of recordId: UUID) {
        for c in fetch(FetchDescriptor<StepCompletionEntity>(predicate: #Predicate { $0.recordId == recordId })) {
            context.delete(c)
        }
        for o in fetch(FetchDescriptor<ObservationEntity>(predicate: #Predicate { $0.recordId == recordId })) {
            context.delete(o)
        }
        for a in fetch(FetchDescriptor<AttachmentEntity>(predicate: #Predicate { $0.recordId == recordId })) {
            if let file = a.localFileName { EvidenceStore.delete(file) }
            context.delete(a)
        }
    }

    private func purge(_ entity: RecordEntity) {
        deleteChildren(of: entity.id)
        context.delete(entity)
    }

    private func save() {
        do {
            try context.save()
        } catch {
            logger.error("SwiftData save failed: \(error.localizedDescription, privacy: .public)")
        }
        version += 1
    }

    private func fetch<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) -> [T] {
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("SwiftData fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func labEntity(_ id: UUID) -> LabEntity? {
        fetch(FetchDescriptor<LabEntity>(predicate: #Predicate { $0.id == id })).first
    }

    private func experimentEntity(_ id: UUID) -> ExperimentEntity? {
        fetch(FetchDescriptor<ExperimentEntity>(predicate: #Predicate { $0.id == id })).first
    }

    private func recordEntity(_ id: UUID) -> RecordEntity? {
        fetch(FetchDescriptor<RecordEntity>(predicate: #Predicate { $0.id == id })).first
    }

    private func observationEntity(recordId: UUID) -> ObservationEntity? {
        fetch(FetchDescriptor<ObservationEntity>(predicate: #Predicate { $0.recordId == recordId })).first
    }

    private func completionEntity(_ id: UUID) -> StepCompletionEntity? {
        fetch(FetchDescriptor<StepCompletionEntity>(predicate: #Predicate { $0.id == id })).first
    }

    private func attachmentEntity(_ id: UUID) -> AttachmentEntity? {
        fetch(FetchDescriptor<AttachmentEntity>(predicate: #Predicate { $0.id == id })).first
    }
}

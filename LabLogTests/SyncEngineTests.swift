import XCTest
@testable import LabLog

/// SyncEngine against a fake backend: outbox draining, per-item results,
/// photo-before-record ordering, and the offline / signed-out short circuits.
@MainActor
final class SyncEngineTests: XCTestCase {
    private var store: SwiftDataStore!
    private var api: FakeAPI!
    private var online = true
    private var signedIn = true

    override func setUp() async throws {
        store = SwiftDataStore(container: try SwiftDataStore.makeContainer(inMemory: true))
        CatalogSeed.installIfNeeded(into: store)
        api = FakeAPI()
        online = true
        signedIn = true
    }

    private var savedPhotos: [UUID: Data] = [:]

    private func makeEngine() -> SyncEngine {
        SyncEngine(api: api, store: store,
                   isOnline: { [unowned self] in online },
                   isSignedIn: { [unowned self] in signedIn },
                   readPhoto: { _ in Data([0xFF, 0xD8]) },
                   downloadPhoto: { _ in Data([0xFF, 0xD8, 0x01]) },
                   savePhoto: { [unowned self] data, id in savedPhotos[id] = data; return "\(id).jpg" })
    }

    /// After signing in on a new or cleared phone, the student's records come
    /// back from the server, with their photos, and a local record wins (ADR-028).
    func testPullRestoresRecordsAndDownloadsTheirPhotos() async {
        let experiment = CatalogSeed.recrystallisation.id
        let step = store.steps(experimentId: experiment)[0]
        let photoId = UUID()
        let remote = SubmissionDTO(
            id: UUID(), studentId: UUID(), studentEmail: nil, experimentId: experiment, status: "submitted",
            latitude: 6.9, longitude: 79.8, createdAt: Date(), submittedAt: Date(),
            stepCompletions: [.init(id: UUID(), stepId: step.id, completedAt: Date(), note: "24.60 mL")],
            observations: [.init(id: UUID(), text: "Crystals formed")],
            attachments: [.init(id: photoId, stepId: step.id, storagePath: "records/x/\(photoId).jpg",
                                url: URL(string: "https://storage.test/photo.jpg"))])
        let local = store.createRecord(experimentId: experiment)
        api.mine = [remote, SubmissionDTO(id: local.id, studentId: UUID(), studentEmail: nil, experimentId: experiment,
                                          status: "submitted", latitude: nil, longitude: nil, createdAt: Date(),
                                          submittedAt: Date(), stepCompletions: [], observations: [], attachments: [])]

        await makeEngine().pullRecords()

        let restored = store.record(id: remote.id)
        XCTAssertEqual(restored?.status, .submitted)
        XCTAssertEqual(restored?.syncState, .synced, "restored records aren't uploaded again")
        XCTAssertEqual(store.completions(recordId: remote.id).first?.note, "24.60 mL")
        XCTAssertEqual(store.observation(recordId: remote.id)?.text, "Crystals formed")
        XCTAssertEqual(store.attachments(recordId: remote.id).first?.localPath, "\(photoId).jpg", "photo downloaded")
        XCTAssertNotNil(savedPhotos[photoId])
        XCTAssertEqual(store.record(id: local.id)?.status, .draft, "the local copy wins")
        XCTAssertEqual(store.pendingRecords().map(\.id), [local.id])
    }

    func testSuccessfulSyncDrainsOutbox() async {
        let record = store.createRecord(experimentId: CatalogSeed.recrystallisation.id)
        let engine = makeEngine()
        XCTAssertEqual(engine.pendingCount, 1)

        await engine.sync()

        XCTAssertEqual(engine.status, .idle)
        XCTAssertEqual(engine.pendingCount, 0)
        XCTAssertEqual(store.record(id: record.id)?.syncState, .synced)
        XCTAssertEqual(api.syncedRecordIds, [record.id])
    }

    func testSyncedTombstoneLeavesTheDevice() async {
        let record = store.createRecord(experimentId: CatalogSeed.recrystallisation.id)
        let engine = makeEngine()
        await engine.sync()                                   // the server now has the draft
        store.discardDraft(id: record.id, sendTombstone: true)
        engine.refreshPendingCount()
        XCTAssertEqual(engine.pendingCount, 1, "the delete waits in the outbox")

        await engine.sync()

        XCTAssertEqual(api.lastPayload?.records.first?.deleted, true)
        XCTAssertEqual(engine.pendingCount, 0)
        XCTAssertTrue(store.pendingRecords().isEmpty)
    }

    func testPhotosUploadBeforeRecordIsPushed() async {
        let record = store.createRecord(experimentId: CatalogSeed.recrystallisation.id)
        let photoId = UUID()
        store.addAttachment(Attachment(id: photoId, recordId: record.id, stepId: nil, localPath: "p.jpg",
                                       storagePath: nil, syncState: .pendingCreate))

        await makeEngine().sync()

        XCTAssertEqual(api.events, ["sign:\(photoId)", "upload:\(photoId)", "sync"])
        XCTAssertEqual(api.lastPayload?.records.first?.attachments.map(\.storagePath), ["records/\(record.id)/\(photoId).jpg"])
        XCTAssertTrue(store.pendingAttachments(recordId: record.id).isEmpty)
    }

    func testServerRejectionMarksOnlyThatRecordFailed() async {
        let good = store.createRecord(experimentId: CatalogSeed.recrystallisation.id)
        let bad = store.createRecord(experimentId: CatalogSeed.titration.id)
        api.rejectIds = [bad.id]
        let engine = makeEngine()

        await engine.sync()

        XCTAssertEqual(store.record(id: good.id)?.syncState, .synced)
        XCTAssertEqual(store.record(id: bad.id)?.syncState, .failed)
        XCTAssertEqual(store.record(id: bad.id)?.lastSyncError, "rejected")
        XCTAssertEqual(engine.status, .failed("rejected"))
        XCTAssertEqual(engine.pendingCount, 1)
    }

    func testNetworkErrorKeepsEverythingQueued() async {
        let record = store.createRecord(experimentId: CatalogSeed.recrystallisation.id)
        api.failSync = true
        let engine = makeEngine()

        await engine.sync()

        XCTAssertEqual(store.record(id: record.id)?.syncState, .failed)
        XCTAssertEqual(engine.pendingCount, 1)
        if case .failed = engine.status {} else { XCTFail("expected failed status, got \(engine.status)") }
    }

    func testOfflineAndSignedOutDoNotCallServer() async {
        _ = store.createRecord(experimentId: CatalogSeed.recrystallisation.id)
        let engine = makeEngine()

        online = false
        await engine.sync()
        XCTAssertEqual(engine.status, .offline)

        online = true
        signedIn = false
        await engine.sync()
        XCTAssertEqual(engine.status, .signedOut)

        XCTAssertTrue(api.events.isEmpty)
        XCTAssertEqual(engine.pendingCount, 1)
    }

    func testNoBackendConfigured() async {
        _ = store.createRecord(experimentId: CatalogSeed.recrystallisation.id)
        let engine = SyncEngine(api: nil, store: store, isOnline: { true }, isSignedIn: { true })
        await engine.sync()
        XCTAssertEqual(engine.status, .notConfigured)
    }

    func testCatalogRefreshSkipsCyclicExperiment() async {
        let lab = Lab(id: UUID(), name: "New Lab", code: "NEW1")
        let okExp = Experiment(id: UUID(), labId: lab.id, title: "OK", description: nil)
        let badExp = Experiment(id: UUID(), labId: lab.id, title: "Cyclic", description: nil)
        let a = UUID(), b = UUID()
        api.catalog = [lab: [
            (okExp, [Step(id: UUID(), experimentId: okExp.id, order: 1, title: "x", instruction: nil,
                          requiresPhoto: false, minDurationSeconds: nil, prerequisiteStepIds: [])]),
            (badExp, [
                Step(id: a, experimentId: badExp.id, order: 1, title: "a", instruction: nil, requiresPhoto: false, minDurationSeconds: nil, prerequisiteStepIds: [b]),
                Step(id: b, experimentId: badExp.id, order: 2, title: "b", instruction: nil, requiresPhoto: false, minDurationSeconds: nil, prerequisiteStepIds: [a]),
            ]),
        ]]

        await makeEngine().refreshCatalog()

        XCTAssertEqual(store.experiments(labId: lab.id).map(\.title), ["OK"])
    }
}

/// In-memory stand-in for the Express backend.
private final class FakeAPI: LabLogAPI {
    var events: [String] = []
    var syncedRecordIds: [UUID] = []
    var lastPayload: SyncRequestDTO?
    var rejectIds: Set<UUID> = []
    var failSync = false
    var catalog: [Lab: [(Experiment, [Step])]] = [:]

    struct Offline: LocalizedError { var errorDescription: String? { "The network connection was lost." } }

    func labs() async throws -> [Lab] { Array(catalog.keys) }

    func experiments(labId: UUID) async throws -> [Experiment] {
        catalog.first { $0.key.id == labId }?.value.map(\.0) ?? []
    }

    func experimentDetail(id: UUID) async throws -> ExperimentDetailDTO {
        let (experiment, steps) = catalog.values.flatMap { $0 }.first { $0.0.id == id }!
        return ExperimentDetailDTO(id: experiment.id, labId: experiment.labId, title: experiment.title,
                                   description: experiment.description, steps: steps)
    }

    func sync(_ payload: SyncRequestDTO) async throws -> SyncResponseDTO {
        events.append("sync")
        if failSync { throw Offline() }
        lastPayload = payload
        return SyncResponseDTO(results: payload.records.map { record in
            if rejectIds.contains(record.id) {
                return SyncItemResultDTO(id: record.id, status: "failed", error: "rejected")
            }
            syncedRecordIds.append(record.id)
            return SyncItemResultDTO(id: record.id, status: "synced", error: nil)
        })
    }

    func signUpload(recordId: UUID, attachmentId: UUID) async throws -> SignUploadDTO {
        events.append("sign:\(attachmentId)")
        let path = "records/\(recordId)/\(attachmentId).jpg"
        return SignUploadDTO(signedUrl: "https://storage.test/\(path)", token: "t", path: path, storagePath: path)
    }

    func submissions(experimentId: UUID) async throws -> [SubmissionDTO] { [] }

    var mine: [SubmissionDTO] = []
    func myRecords() async throws -> [SubmissionDTO] { mine }

    func uploadPhoto(_ data: Data, to signed: SignUploadDTO) async throws {
        events.append("upload:\(signed.path.split(separator: "/").last!.dropLast(4))")
    }
}

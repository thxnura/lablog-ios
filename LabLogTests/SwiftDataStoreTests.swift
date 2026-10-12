import XCTest
@testable import LabLog

/// The outbox rules of the local store, against an in-memory SwiftData container.
@MainActor
final class SwiftDataStoreTests: XCTestCase {
    private var store: SwiftDataStore!
    private let experimentId = CatalogSeed.recrystallisation.id

    override func setUp() async throws {
        store = SwiftDataStore(container: try SwiftDataStore.makeContainer(inMemory: true))
        CatalogSeed.installIfNeeded(into: store)
    }

    func testSeedLoadsOnce() {
        XCTAssertEqual(store.labs().count, 2)
        XCTAssertEqual(store.steps(experimentId: experimentId).map(\.order), [1, 2, 3, 4])
        CatalogSeed.installIfNeeded(into: store)
        XCTAssertEqual(store.labs().count, 2)
    }

    func testNewRecordIsInOutbox() {
        let record = store.createRecord(experimentId: experimentId)
        XCTAssertEqual(record.syncState, .pendingCreate)
        XCTAssertEqual(store.pendingRecords().map(\.id), [record.id])
    }

    func testSyncedRecordRequeuesOnEdit() {
        let record = store.createRecord(experimentId: experimentId)
        store.applySyncResult(id: record.id, synced: true, sentRevision: record.revision, error: nil)
        XCTAssertTrue(store.pendingRecords().isEmpty)

        let step = store.steps(experimentId: experimentId)[0]
        store.addCompletion(StepCompletion(id: UUID(), recordId: record.id, stepId: step.id, completedAt: Date()))
        XCTAssertEqual(store.record(id: record.id)?.syncState, .pendingUpdate)
    }

    /// An edit while the sync request is in flight must not be lost.
    func testEditDuringSyncKeepsRecordPending() {
        let record = store.createRecord(experimentId: experimentId)
        let sentRevision = record.revision
        store.setObservation(recordId: record.id, text: "white crystals") // edit mid-flight
        store.applySyncResult(id: record.id, synced: true, sentRevision: sentRevision, error: nil)
        XCTAssertEqual(store.record(id: record.id)?.syncState, .pendingUpdate)
    }

    func testFailedSyncStaysInOutboxWithError() {
        let record = store.createRecord(experimentId: experimentId)
        store.applySyncResult(id: record.id, synced: false, sentRevision: record.revision, error: "Server returned 500")
        let pending = store.pendingRecords()
        XCTAssertEqual(pending.first?.syncState, .failed)
        XCTAssertEqual(pending.first?.lastSyncError, "Server returned 500")
    }

    func testDuplicateCompletionIgnored() {
        let record = store.createRecord(experimentId: experimentId)
        let step = store.steps(experimentId: experimentId)[0]
        store.addCompletion(StepCompletion(id: UUID(), recordId: record.id, stepId: step.id, completedAt: Date()))
        store.addCompletion(StepCompletion(id: UUID(), recordId: record.id, stepId: step.id, completedAt: Date()))
        XCTAssertEqual(store.completions(recordId: record.id).count, 1)
    }

    func testDTOOnlyIncludesUploadedPhotos() {
        let record = store.createRecord(experimentId: experimentId)
        let uploaded = UUID(), waiting = UUID()
        store.addAttachment(Attachment(id: uploaded, recordId: record.id, stepId: nil, localPath: "a.jpg", storagePath: nil, syncState: .pendingCreate))
        store.addAttachment(Attachment(id: waiting, recordId: record.id, stepId: nil, localPath: "b.jpg", storagePath: nil, syncState: .pendingCreate))
        store.markAttachmentUploaded(uploaded, storagePath: "records/x/a.jpg")
        store.setObservation(recordId: record.id, text: "  ")

        let dto = store.makeDTO(store.record(id: record.id)!)
        XCTAssertEqual(dto.attachments.map(\.id), [uploaded])
        XCTAssertTrue(dto.observations.isEmpty, "blank observations are not sent")
        XCTAssertEqual(store.pendingAttachments(recordId: record.id).map(\.id), [waiting])
    }

    func testSubmitStampsLocationOnce() {
        let record = store.createRecord(experimentId: experimentId)
        store.submitRecord(id: record.id, latitude: 6.9, longitude: 79.8)
        store.submitRecord(id: record.id, latitude: 0, longitude: 0) // ignored: already submitted
        let saved = store.record(id: record.id)
        XCTAssertEqual(saved?.status, .submitted)
        XCTAssertEqual(saved?.latitude, 6.9)
        XCTAssertNotNil(saved?.submittedAt)
    }

    func testReplaceCatalogReplacesStepGraph() {
        let newStep = Step(id: UUID(), experimentId: experimentId, order: 1, title: "Only step",
                           instruction: nil, requiresPhoto: false, minDurationSeconds: nil, prerequisiteStepIds: [])
        store.replaceCatalog(labs: [CatalogSeed.chemistryLab], experiments: [CatalogSeed.recrystallisation], steps: [newStep])
        XCTAssertEqual(store.steps(experimentId: experimentId).map(\.title), ["Only step"])
        XCTAssertEqual(store.labs().count, 2, "labs are upserted, not wiped")
    }
}

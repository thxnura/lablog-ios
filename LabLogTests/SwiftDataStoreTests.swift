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

    /// Signing out clears the student's work from the iPhone but keeps the catalog.
    func testRemoveAllRecordsKeepsTheCatalog() {
        let synced = store.createRecord(experimentId: experimentId)
        store.applySyncResult(id: synced.id, synced: true, sentRevision: synced.revision, error: nil)
        let draft = store.createRecord(experimentId: experimentId)
        let step = store.steps(experimentId: experimentId)[0]
        store.addCompletion(StepCompletion(id: UUID(), recordId: draft.id, stepId: step.id, completedAt: Date()))
        store.setObservation(recordId: draft.id, text: "Crystals formed")
        store.addAttachment(Attachment(id: UUID(), recordId: draft.id, stepId: step.id, localPath: nil,
                                       storagePath: nil, syncState: .pendingCreate))

        store.removeAllRecords()

        XCTAssertTrue(store.records().isEmpty)
        XCTAssertTrue(store.pendingRecords().isEmpty, "nothing left to upload to the next account")
        XCTAssertTrue(store.completions(recordId: draft.id).isEmpty)
        XCTAssertNil(store.observation(recordId: draft.id))
        XCTAssertTrue(store.attachments(recordId: draft.id).isEmpty)
        XCTAssertEqual(store.labs().count, 2, "the catalog stays")
        XCTAssertEqual(store.steps(experimentId: experimentId).count, 4)
    }

    /// Restoring twice adds a server record once, and never touches a local one.
    func testRestoreIsIdempotentAndKeepsLocalRecords() {
        let remoteId = UUID()
        let remote = SubmissionDTO(id: remoteId, studentId: UUID(), studentEmail: nil, experimentId: experimentId,
                                   status: "draft", latitude: nil, longitude: nil, createdAt: Date(), submittedAt: nil,
                                   stepCompletions: [], observations: [], attachments: [])
        XCTAssertTrue(store.restore([remote]).isEmpty, "no photos to fetch")
        _ = store.restore([remote])
        XCTAssertEqual(store.records().filter { $0.id == remoteId }.count, 1)
        XCTAssertEqual(store.record(id: remoteId)?.syncState, .synced)
        XCTAssertTrue(store.pendingRecords().isEmpty)
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

    // MARK: Discarding drafts (tombstones)

    func testDiscardingANeverSentDraftRemovesItAtOnce() {
        let record = store.createRecord(experimentId: experimentId)
        store.setObservation(recordId: record.id, text: "spilled")
        store.discardDraft(id: record.id, sendTombstone: true)
        XCTAssertNil(store.record(id: record.id))
        XCTAssertTrue(store.pendingRecords().isEmpty, "nothing to tell the server")
        XCTAssertNil(store.observation(recordId: record.id))
    }

    func testDiscardingASentDraftLeavesATombstoneUntilSynced() {
        let record = store.createRecord(experimentId: experimentId)
        let step = store.steps(experimentId: experimentId)[0]
        store.addCompletion(StepCompletion(id: UUID(), recordId: record.id, stepId: step.id, completedAt: Date()))
        store.applySyncResult(id: record.id, synced: true, sentRevision: store.record(id: record.id)!.revision, error: nil)

        store.discardDraft(id: record.id, sendTombstone: true)

        XCTAssertNil(store.record(id: record.id), "hidden from the app")
        XCTAssertTrue(store.records().isEmpty)
        let tombstone = try! XCTUnwrap(store.pendingRecords().first)
        let dto = store.makeDTO(tombstone)
        XCTAssertEqual(dto.deleted, true)
        XCTAssertTrue(dto.stepCompletions.isEmpty)

        store.applySyncResult(id: record.id, synced: true, sentRevision: tombstone.revision, error: nil)
        XCTAssertTrue(store.pendingRecords().isEmpty, "a synced tombstone is purged")
    }

    func testOnlyDraftsCanBeDiscarded() {
        let record = store.createRecord(experimentId: experimentId)
        store.submitRecord(id: record.id, latitude: nil, longitude: nil)
        store.discardDraft(id: record.id, sendTombstone: true)
        XCTAssertEqual(store.record(id: record.id)?.status, .submitted)
    }

    // MARK: Photos and notes

    func testRemovingAPhotoRequeuesTheRecordAndLeavesTheDTO() {
        let record = store.createRecord(experimentId: experimentId)
        let photo = UUID()
        store.addAttachment(Attachment(id: photo, recordId: record.id, stepId: nil, localPath: "x.jpg",
                                       storagePath: nil, syncState: .pendingCreate))
        store.markAttachmentUploaded(photo, storagePath: "records/x/x.jpg")
        store.applySyncResult(id: record.id, synced: true, sentRevision: store.record(id: record.id)!.revision, error: nil)

        store.removeAttachment(id: photo)

        XCTAssertEqual(store.record(id: record.id)?.syncState, .pendingUpdate)
        XCTAssertTrue(store.makeDTO(store.record(id: record.id)!).attachments.isEmpty,
                      "the server drops photos missing from the set")
    }

    func testStepNoteSyncsAndABlankNoteClearsIt() {
        let record = store.createRecord(experimentId: experimentId)
        let step = store.steps(experimentId: experimentId)[0]
        let completion = StepCompletion(id: UUID(), recordId: record.id, stepId: step.id, completedAt: Date())
        store.addCompletion(completion)
        store.applySyncResult(id: record.id, synced: true, sentRevision: store.record(id: record.id)!.revision, error: nil)

        store.setCompletionNote(id: completion.id, note: "  m = 2.31 g  ")
        XCTAssertEqual(store.makeDTO(store.record(id: record.id)!).stepCompletions.first?.note, "m = 2.31 g")
        XCTAssertEqual(store.record(id: record.id)?.syncState, .pendingUpdate)

        store.setCompletionNote(id: completion.id, note: "   ")
        XCTAssertNil(store.completions(recordId: record.id).first?.note)
    }

    func testSubmittedRecordsCantBeEdited() {
        let record = store.createRecord(experimentId: experimentId)
        let step = store.steps(experimentId: experimentId)[0]
        let completion = StepCompletion(id: UUID(), recordId: record.id, stepId: step.id, completedAt: Date())
        store.addCompletion(completion)
        let photo = UUID()
        store.addAttachment(Attachment(id: photo, recordId: record.id, stepId: step.id, localPath: "y.jpg",
                                       storagePath: nil, syncState: .pendingCreate))
        store.submitRecord(id: record.id, latitude: nil, longitude: nil)

        store.setCompletionNote(id: completion.id, note: "too late")
        store.removeAttachment(id: photo)

        XCTAssertNil(store.completions(recordId: record.id).first?.note)
        XCTAssertEqual(store.attachments(recordId: record.id).map(\.id), [photo])
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

    /// A refresh keeps only the labs the server lists for this account (ADR-029).
    func testKeepOnlyLabsDropsUnlistedLabsWithTheirExperiments() {
        store.keepOnlyLabs([CatalogSeed.chemistryLab.id])
        XCTAssertEqual(store.labs().map(\.id), [CatalogSeed.chemistryLab.id])
        XCTAssertNotNil(store.experiment(id: experimentId), "chemistry's experiments stay")
        XCTAssertTrue(store.experiments(labId: CatalogSeed.physicsLab.id).isEmpty)
    }
}

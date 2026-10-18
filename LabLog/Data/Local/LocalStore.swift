import Foundation

/// Local, offline-first persistence boundary. The rest of the app treats
/// storage abstractly; the production implementation is `SwiftDataStore`.
/// Every user action writes here first — the network is a background concern.
@MainActor
protocol LocalStore: AnyObject {
    /// Bumped after every write. Views key their reloads on it
    /// (`.task(id: store.version)`) so they refresh when data changes.
    var version: Int { get }

    // MARK: Catalog cache
    func hasCatalog() -> Bool
    /// Upserts labs/experiments and replaces each given experiment's steps.
    func replaceCatalog(labs: [Lab], experiments: [Experiment], steps: [Step])
    func labs() -> [Lab]
    func experiments(labId: UUID) -> [Experiment]
    func experiment(id: UUID) -> Experiment?
    func steps(experimentId: UUID) -> [Step]

    // MARK: Records
    func createRecord(experimentId: UUID) -> LabRecord
    func record(id: UUID) -> LabRecord?
    /// All records, newest first.
    func records() -> [LabRecord]
    func records(experimentId: UUID) -> [LabRecord]
    func completions(recordId: UUID) -> [StepCompletion]
    func observation(recordId: UUID) -> LabObservation?
    func attachments(recordId: UUID) -> [Attachment]

    func addCompletion(_ completion: StepCompletion)
    /// A student's note on a completed step (nil or blank clears it).
    func setCompletionNote(id: UUID, note: String?)
    func setObservation(recordId: UUID, text: String)
    func addAttachment(_ attachment: Attachment)
    /// Deletes a photo and its file (retake or remove). Drafts only.
    func removeAttachment(id: UUID)
    func submitRecord(id: UUID, latitude: Double?, longitude: Double?)
    /// Discards a draft. If the server may have it (it was ever sent), the
    /// record stays in the outbox as a tombstone until the delete syncs;
    /// otherwise, or with no server, it is removed at once. Drafts only.
    func discardDraft(id: UUID, sendTombstone: Bool)

    // MARK: Account
    /// Deletes every record with its steps, notes, observation and photos
    /// (files too); the catalog stays. Signing out uses it, so the next person
    /// on this iPhone neither sees the work nor uploads it to their account.
    func removeAllRecords()

    // MARK: Outbox
    /// Records that are not `synced` (pending or failed), oldest first.
    func pendingRecords() -> [LabRecord]
    /// Photos for a record that still need uploading.
    func pendingAttachments(recordId: UUID) -> [Attachment]
    func makeDTO(_ record: LabRecord) -> SyncRecordDTO

    // MARK: Sync reconciliation
    func markAttachmentUploaded(_ id: UUID, storagePath: String)
    /// The local file for this photo is gone; stop trying to upload it.
    func markAttachmentLost(_ id: UUID)
    /// `sentRevision` is the record's revision when its DTO was built. If the
    /// record was edited since, it stays pending so the edit is synced too.
    /// A synced tombstone is removed from the device.
    func applySyncResult(id: UUID, synced: Bool, sentRevision: Int, error: String?)
}

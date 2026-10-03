import Foundation

/// Local, offline-first persistence boundary. This protocol lets the rest of
/// the app treat storage abstractly; the production implementation is backed by
/// SwiftData (see `SwiftDataStore`). Writes happen here first, always.
protocol LocalStore {
    // Catalog cache
    func cacheLabs(_ labs: [Lab])
    func cachedLabs() -> [Lab]
    func cacheExperiment(_ experiment: Experiment, steps: [Step])
    func steps(experimentId: UUID) -> [Step]

    // Records (outbox)
    func upsertRecord(_ record: LabRecord)
    func addCompletion(_ completion: StepCompletion)
    func addObservation(_ observation: Observation)
    func addAttachment(_ attachment: Attachment)

    func pendingRecords() -> [LabRecord]
    func pendingAttachments(recordId: UUID) -> [Attachment]

    // Sync reconciliation
    func makeDTO(_ record: LabRecord) -> SyncRecordDTO
    func markAttachmentSynced(_ id: UUID, storagePath: String)
    func applySyncResult(id: UUID, synced: Bool)
}

// NOTE: Implement `SwiftDataStore: LocalStore` once the Xcode project exists
// (SwiftData @Model types mirror the structs in Domain/Entities). Kept as a
// protocol here so ViewModels and SyncEngine can be built and tested first.

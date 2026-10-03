import Foundation

// MARK: - Catalog (pulled from backend, cached locally)

struct Lab: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let code: String
}

struct Experiment: Identifiable, Codable, Hashable {
    let id: UUID
    let labId: UUID
    let title: String
    let description: String?
}

struct Step: Identifiable, Codable, Hashable {
    let id: UUID
    let experimentId: UUID
    let order: Int
    let title: String
    let instruction: String?
    /// Guard: a photo must be attached before this step can be completed.
    let requiresPhoto: Bool
    /// Guard: cannot complete until this many seconds elapse (e.g. a timer).
    let minDurationSeconds: Int?
    /// Precedence edges: these steps must be complete before this one unlocks.
    let prerequisiteStepIds: [UUID]
}

// MARK: - Record (created on device, synced up)

enum RecordStatus: String, Codable { case draft, submitted }

/// Local-only: where a record is in the sync lifecycle. Never sent to server.
enum SyncState: String, Codable {
    case pendingCreate
    case pendingUpdate
    case synced
    case failed
}

struct LabRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let experimentId: UUID
    var status: RecordStatus
    var syncState: SyncState
    var latitude: Double?
    var longitude: Double?
    let createdAt: Date
    var submittedAt: Date?
}

struct StepCompletion: Identifiable, Codable, Hashable {
    let id: UUID
    let recordId: UUID
    let stepId: UUID
    let completedAt: Date
    var note: String?
}

struct Observation: Identifiable, Codable, Hashable {
    let id: UUID
    let recordId: UUID
    var text: String
}

struct Attachment: Identifiable, Codable, Hashable {
    let id: UUID
    let recordId: UUID
    let stepId: UUID?
    /// Local file URL before upload; set to the Storage path after sync.
    var localPath: String?
    var storagePath: String?
    var syncState: SyncState
}

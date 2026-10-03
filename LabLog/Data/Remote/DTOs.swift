import Foundation

/// Wire DTOs matching the Express backend's zod contracts (camelCase JSON).

struct SyncStepCompletionDTO: Codable {
    let id: UUID
    let stepId: UUID
    let completedAt: Date
    let note: String?
}

struct SyncObservationDTO: Codable {
    let id: UUID
    let text: String
}

struct SyncAttachmentDTO: Codable {
    let id: UUID
    let stepId: UUID?
    let storagePath: String
}

struct SyncRecordDTO: Codable {
    let id: UUID
    let experimentId: UUID
    let status: String
    let latitude: Double?
    let longitude: Double?
    let createdAt: Date
    let submittedAt: Date?
    let stepCompletions: [SyncStepCompletionDTO]
    let observations: [SyncObservationDTO]
    let attachments: [SyncAttachmentDTO]
}

struct SyncRequestDTO: Codable { let records: [SyncRecordDTO] }

struct SyncItemResultDTO: Codable {
    let id: UUID
    let status: String   // "synced" | "failed"
    let error: String?
}

struct SyncResponseDTO: Codable { let results: [SyncItemResultDTO] }

struct SignUploadDTO: Codable {
    let signedUrl: String
    let token: String
    let path: String
    let storagePath: String
}

import Foundation

/// Wire DTOs matching the Express backend's zod contracts (camelCase JSON).

struct SyncStepCompletionDTO: Codable, Equatable {
    let id: UUID
    let stepId: UUID
    let completedAt: Date
    let note: String?
}

struct SyncObservationDTO: Codable, Equatable {
    let id: UUID
    let text: String
}

struct SyncAttachmentDTO: Codable, Equatable {
    let id: UUID
    let stepId: UUID?
    let storagePath: String
}

struct SyncRecordDTO: Codable, Equatable {
    let id: UUID
    let experimentId: UUID
    let status: String
    let latitude: Double?
    let longitude: Double?
    let createdAt: Date
    let submittedAt: Date?
    let stepCompletions: [SyncStepCompletionDTO]
    let observations: [SyncObservationDTO]
    /// The record's full set of uploaded photos: the server drops any it has
    /// that aren't listed (a retaken or removed photo).
    let attachments: [SyncAttachmentDTO]
    /// Tombstone: the draft was discarded on the device. Omitted otherwise.
    var deleted: Bool? = nil
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

/// `GET /api/experiments/:id` — an experiment with its ordered steps.
struct ExperimentDetailDTO: Codable {
    let id: UUID
    let labId: UUID
    let title: String
    let description: String?
    let steps: [Step]

    var experiment: Experiment {
        Experiment(id: id, labId: labId, title: title, description: description)
    }
}

/// `GET /api/records?experimentId=` — one submitted record, as a lecturer sees it.
/// `GET /api/records/mine` returns the student's own records in the same shape.
struct SubmissionDTO: Decodable, Identifiable, Hashable {
    struct Completion: Decodable, Hashable {
        let id: UUID
        let stepId: UUID
        let completedAt: Date
        let note: String?
    }

    struct Note: Decodable, Hashable {
        let id: UUID
        let text: String
    }

    struct Photo: Decodable, Hashable, Identifiable {
        let id: UUID
        let stepId: UUID?
        let storagePath: String
        /// Signed, time-limited (1 h) download URL for the private bucket.
        let url: URL?
    }

    let id: UUID
    let studentId: UUID
    let studentEmail: String?
    let experimentId: UUID
    let status: String
    let latitude: Double?
    let longitude: Double?
    let createdAt: Date
    let submittedAt: Date?
    let stepCompletions: [Completion]
    let observations: [Note]
    let attachments: [Photo]
}

/// Error body produced by the backend's errorHandler: `{ "error": "…" }`.
struct APIErrorBody: Decodable { let error: String }

import Foundation
import SwiftData

// SwiftData @Model classes that mirror the plain Domain structs. The store maps
// between them at its boundary, so the Domain layer stays free of SwiftData.
// Children reference their parent by id (no @Relationship) to keep the outbox
// queries simple and the mapping one-to-one with the backend tables.
// Enums are stored as raw strings so they can be used inside #Predicate.

@Model
final class LabEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var code: String

    init(_ lab: Lab) {
        id = lab.id
        name = lab.name
        code = lab.code
    }

    var domain: Lab { Lab(id: id, name: name, code: code) }
}

@Model
final class ExperimentEntity {
    @Attribute(.unique) var id: UUID
    var labId: UUID
    var title: String
    var summary: String?

    init(_ experiment: Experiment) {
        id = experiment.id
        labId = experiment.labId
        title = experiment.title
        summary = experiment.description
    }

    var domain: Experiment { Experiment(id: id, labId: labId, title: title, description: summary) }
}

@Model
final class StepEntity {
    @Attribute(.unique) var id: UUID
    var experimentId: UUID
    var position: Int
    var title: String
    var instruction: String?
    var requiresPhoto: Bool
    var minDurationSeconds: Int?
    var prerequisiteStepIds: [UUID]
    // Guide content (added in catalog v2 — optional so existing stores migrate).
    var guideSteps: [String]?
    var safetyNote: String?
    var expectedResult: String?

    init(_ step: Step) {
        id = step.id
        experimentId = step.experimentId
        position = step.order
        title = step.title
        instruction = step.instruction
        requiresPhoto = step.requiresPhoto
        minDurationSeconds = step.minDurationSeconds
        prerequisiteStepIds = step.prerequisiteStepIds
        guideSteps = step.guide?.steps
        safetyNote = step.guide?.safety
        expectedResult = step.guide?.expected
    }

    var domain: Step {
        let guide = StepGuide(steps: guideSteps ?? [], safety: safetyNote, expected: expectedResult)
        return Step(id: id, experimentId: experimentId, order: position, title: title,
                    instruction: instruction, requiresPhoto: requiresPhoto,
                    minDurationSeconds: minDurationSeconds, prerequisiteStepIds: prerequisiteStepIds,
                    guide: guide.isEmpty ? nil : guide)
    }
}

@Model
final class RecordEntity {
    @Attribute(.unique) var id: UUID
    var experimentId: UUID
    var statusRaw: String
    var syncStateRaw: String
    var latitude: Double?
    var longitude: Double?
    var createdAt: Date
    var submittedAt: Date?
    var revision: Int
    var lastSyncError: String?

    init(id: UUID, experimentId: UUID, createdAt: Date) {
        self.id = id
        self.experimentId = experimentId
        statusRaw = RecordStatus.draft.rawValue
        syncStateRaw = SyncState.pendingCreate.rawValue
        self.createdAt = createdAt
        revision = 1
    }

    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .pendingUpdate }
        set { syncStateRaw = newValue.rawValue }
    }

    var status: RecordStatus {
        get { RecordStatus(rawValue: statusRaw) ?? .draft }
        set { statusRaw = newValue.rawValue }
    }

    var domain: LabRecord {
        LabRecord(id: id, experimentId: experimentId, status: status, syncState: syncState,
                  latitude: latitude, longitude: longitude, createdAt: createdAt,
                  submittedAt: submittedAt, revision: revision, lastSyncError: lastSyncError)
    }
}

@Model
final class StepCompletionEntity {
    @Attribute(.unique) var id: UUID
    var recordId: UUID
    var stepId: UUID
    var completedAt: Date
    var note: String?

    init(_ completion: StepCompletion) {
        id = completion.id
        recordId = completion.recordId
        stepId = completion.stepId
        completedAt = completion.completedAt
        note = completion.note
    }

    var domain: StepCompletion {
        StepCompletion(id: id, recordId: recordId, stepId: stepId, completedAt: completedAt, note: note)
    }
}

@Model
final class ObservationEntity {
    @Attribute(.unique) var id: UUID
    var recordId: UUID
    var text: String

    init(id: UUID, recordId: UUID, text: String) {
        self.id = id
        self.recordId = recordId
        self.text = text
    }

    var domain: LabObservation { LabObservation(id: id, recordId: recordId, text: text) }
}

@Model
final class AttachmentEntity {
    @Attribute(.unique) var id: UUID
    var recordId: UUID
    var stepId: UUID?
    var localFileName: String?
    var storagePath: String?
    var syncStateRaw: String
    var createdAt: Date

    init(_ attachment: Attachment, createdAt: Date) {
        id = attachment.id
        recordId = attachment.recordId
        stepId = attachment.stepId
        localFileName = attachment.localPath
        storagePath = attachment.storagePath
        syncStateRaw = attachment.syncState.rawValue
        self.createdAt = createdAt
    }

    var domain: Attachment {
        Attachment(id: id, recordId: recordId, stepId: stepId, localPath: localFileName,
                   storagePath: storagePath, syncState: SyncState(rawValue: syncStateRaw) ?? .pendingCreate)
    }
}

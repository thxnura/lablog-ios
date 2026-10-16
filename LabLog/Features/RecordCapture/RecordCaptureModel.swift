import Foundation
import Observation
import UIKit

/// State + actions for the capture screen. Every action writes to the local
/// store first, then nudges the SyncEngine — the UI never waits on the network.
@MainActor
@Observable
final class RecordCaptureModel {
    let recordId: UUID

    private(set) var record: LabRecord?
    private(set) var experiment: Experiment?
    private(set) var steps: [Step] = []
    var completions: [StepCompletion] = []
    private(set) var attachments: [Attachment] = []
    var observationText = ""
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let engine = StepConstraintEngine()
    @ObservationIgnored private var observationSaveTask: Task<Void, Never>?
    @ObservationIgnored private var noteSaveTasks: [UUID: Task<Void, Never>] = [:]

    /// Same limit as the backend's zod schema for a completion note.
    static let noteLimit = 2000

    init(recordId: UUID, app: AppModel) {
        self.recordId = recordId
        self.app = app
    }

    var isEditable: Bool { record?.status == .draft }

    var photoStepIds: Set<UUID> { Set(attachments.compactMap(\.stepId)) }

    var completedCount: Int { completions.count }

    var canSubmit: Bool {
        isEditable && !isSubmitting
            && engine.isComplete(steps, completedStepIds: Set(completions.map(\.stepId)))
    }

    /// Reload everything from the store (cheap; called whenever it changes).
    func load() {
        let store = app.store
        record = store.record(id: recordId)
        guard let record else { return }
        experiment = store.experiment(id: record.experimentId)
        steps = store.steps(experimentId: record.experimentId)
        completions = store.completions(recordId: recordId)
        attachments = store.attachments(recordId: recordId)
        // Don't clobber text the student is typing with an older saved copy.
        if observationSaveTask == nil {
            observationText = store.observation(recordId: recordId)?.text ?? ""
        }
        // Keep the Dynamic Island timer in step with the checklist.
        app.refreshTimers(recordId: recordId)
    }

    /// The timed step currently waiting (drives the guide's timer dial).
    var timedStep: StepTimerCoordinator.TimedStep? {
        guard isEditable else { return nil }
        return StepTimerCoordinator.timedStep(steps: steps, completions: completions)
    }

    /// Complete a step from the step guide. Goes through the same constraint
    /// check as everywhere else; returns false if the step is still locked.
    @discardableResult
    func complete(_ step: Step) -> Bool {
        let done = app.completeStep(recordId: recordId, stepId: step.id)
        load()
        return done
    }

    // MARK: Actions

    func persist(_ completion: StepCompletion) {
        app.store.addCompletion(completion)
        app.didChangeLocally()
    }

    /// Saves the photo as evidence for `step`, then completes the step if that
    /// was the last thing it was waiting for. A retake replaces the step's
    /// photo — the old one is only deleted once the new one is safely saved.
    func attachPhoto(_ image: UIImage, to step: Step) {
        guard isEditable else { return }
        let previous = attachments.filter { $0.stepId == step.id }
        let attachmentId = UUID()
        do {
            let fileName = try EvidenceStore.save(image, id: attachmentId)
            app.store.addAttachment(Attachment(id: attachmentId, recordId: recordId, stepId: step.id,
                                               localPath: fileName, storagePath: nil, syncState: .pendingCreate))
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        for old in previous { app.store.removeAttachment(id: old.id) }
        load()

        let context = StepConstraintEngine.Context(
            completedStepIds: Set(completions.map(\.stepId)),
            attachedPhotoStepIds: photoStepIds,
            completionTimes: Dictionary(completions.map { ($0.stepId, $0.completedAt) }, uniquingKeysWith: { a, _ in a }),
            now: Date(),
        )
        if !completions.contains(where: { $0.stepId == step.id }), engine.isUnlocked(step, context: context) {
            let completion = StepCompletion(id: UUID(), recordId: recordId, stepId: step.id, completedAt: Date(), note: nil)
            completions.append(completion)
            app.store.addCompletion(completion)
        }
        app.didChangeLocally()
    }

    func photo(for step: Step) -> Attachment? {
        attachments.last { $0.stepId == step.id }
    }

    /// A photo can be removed until its step is done; after that it is the
    /// evidence the completion rests on (it can still be retaken).
    func canRemovePhoto(of step: Step) -> Bool {
        isEditable && photo(for: step) != nil && !completions.contains { $0.stepId == step.id }
    }

    func removePhoto(of step: Step) {
        guard canRemovePhoto(of: step) else { return }
        for attachment in attachments where attachment.stepId == step.id {
            app.store.removeAttachment(id: attachment.id)
        }
        load()
        app.didChangeLocally()
    }

    func note(for step: Step) -> String {
        completions.first { $0.stepId == step.id }?.note ?? ""
    }

    /// Debounced like the observation; the note lives on the step's completion.
    func noteChanged(_ text: String, for step: Step) {
        guard isEditable, completions.contains(where: { $0.stepId == step.id }) else { return }
        noteSaveTasks[step.id]?.cancel()
        noteSaveTasks[step.id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, !Task.isCancelled else { return }
            self.saveNoteNow(text, for: step)
        }
    }

    func saveNoteNow(_ text: String, for step: Step) {
        noteSaveTasks[step.id]?.cancel()
        noteSaveTasks[step.id] = nil
        guard isEditable, let completion = completions.first(where: { $0.stepId == step.id }) else { return }
        app.store.setCompletionNote(id: completion.id, note: String(text.prefix(Self.noteLimit)))
        app.didChangeLocally()
    }

    /// Throws the draft away (see AppModel.discardDraft).
    func discard() {
        guard isEditable else { return }
        observationSaveTask?.cancel()
        observationSaveTask = nil
        noteSaveTasks.values.forEach { $0.cancel() }
        noteSaveTasks = [:]
        app.discardDraft(recordId: recordId)
    }

    /// Debounced so typing doesn't write on every keystroke.
    func observationChanged() {
        guard isEditable else { return }
        observationSaveTask?.cancel()
        observationSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self, !Task.isCancelled else { return }
            self.saveObservationNow()
        }
    }

    func saveObservationNow() {
        observationSaveTask?.cancel()
        observationSaveTask = nil
        guard isEditable else { return }
        app.store.setObservation(recordId: recordId, text: observationText)
        app.didChangeLocally()
    }

    /// Stamp location (best effort, bounded wait) and mark the record submitted.
    func submit() async {
        guard isEditable, !isSubmitting,
              engine.isComplete(steps, completedStepIds: Set(completions.map(\.stepId))) else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        saveObservationNow()
        let coordinate = await app.location.currentCoordinate()
        app.store.submitRecord(id: recordId, latitude: coordinate?.latitude, longitude: coordinate?.longitude)
        app.didChangeLocally()
        load()
    }

    func clearError() { errorMessage = nil }
}

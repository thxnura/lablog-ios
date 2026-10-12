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
    }

    // MARK: Actions

    func persist(_ completion: StepCompletion) {
        app.store.addCompletion(completion)
        app.didChangeLocally()
    }

    /// Saves the photo as evidence for `step`, then completes the step if that
    /// was the last thing it was waiting for.
    func attachPhoto(_ image: UIImage, to step: Step) {
        let attachmentId = UUID()
        do {
            let fileName = try EvidenceStore.save(image, id: attachmentId)
            app.store.addAttachment(Attachment(id: attachmentId, recordId: recordId, stepId: step.id,
                                               localPath: fileName, storagePath: nil, syncState: .pendingCreate))
        } catch {
            errorMessage = error.localizedDescription
            return
        }
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
        guard canSubmit else { return }
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

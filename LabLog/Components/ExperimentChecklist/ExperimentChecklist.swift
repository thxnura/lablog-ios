import SwiftUI

/// ★ Custom component.
///
/// Renders an ordered, precedence-constrained list of experiment steps and
/// enforces the "can't do Step N+1 before Step N" rule through the injected
/// `StepConstraintEngine`.
///
/// Properties (inputs):
///   - steps:        the ordered steps to render
///   - completions:  two-way bound completion state
///   - photoStepIds: steps that currently have a photo attached
///   - engine:       the constraint engine (unlock logic)
///   - style:        theming
///
/// Events (outputs):
///   - onStepCompleted(Step)        a step was marked done → re-eval the DAG
///   - onPhotoRequested(Step)       a requiresPhoto step needs the camera
///   - onLockedStepTapped(Step,msg) user tapped a locked step → surface reason
struct ExperimentChecklist: View {
    let steps: [Step]
    @Binding var completions: [StepCompletion]
    let photoStepIds: Set<UUID>
    var engine: StepConstraintEngine = StepConstraintEngine()
    var style: ChecklistStyle = .default

    var onStepCompleted: (Step) -> Void = { _ in }
    var onPhotoRequested: (Step) -> Void = { _ in }
    var onLockedStepTapped: (Step, String) -> Void = { _, _ in }

    /// Re-created each render so timers/prereqs reflect the latest state.
    private var context: StepConstraintEngine.Context {
        let completed = Set(completions.map(\.stepId))
        let times = Dictionary(
            completions.map { ($0.stepId, $0.completedAt) },
            uniquingKeysWith: { a, _ in a },
        )
        return .init(
            completedStepIds: completed,
            attachedPhotoStepIds: photoStepIds,
            completionTimes: times,
            now: Date(),
        )
    }

    var body: some View {
        VStack(spacing: style.rowSpacing) {
            ForEach(steps.sorted(by: { $0.order < $1.order })) { step in
                ChecklistRow(
                    step: step,
                    state: rowState(for: step),
                    style: style,
                    onTap: { handleTap(step) },
                )
            }
        }
    }

    private func rowState(for step: Step) -> ChecklistRow.RowState {
        if let completion = completions.first(where: { $0.stepId == step.id }) {
            return .completed(at: completion.completedAt)
        }
        if let reason = engine.lockReason(for: step, context: context) {
            switch reason {
            case .needsPhoto:
                return .needsPhoto
            case .timerPending(let secs):
                let m = secs / 60, s = secs % 60
                return .timerPending(text: String(format: "Wait %d:%02d", m, s))
            case .prerequisitesIncomplete:
                return .locked(reason: engine.message(for: reason, steps: steps))
            }
        }
        return .available
    }

    private func handleTap(_ step: Step) {
        guard !completions.contains(where: { $0.stepId == step.id }) else { return }

        if let reason = engine.lockReason(for: step, context: context) {
            if case .needsPhoto = reason {
                onPhotoRequested(step)
            } else {
                onLockedStepTapped(step, engine.message(for: reason, steps: steps))
            }
            return
        }

        // Unlocked → complete it, then re-evaluation unlocks successors.
        let completion = StepCompletion(
            id: UUID(),
            recordId: completions.first?.recordId ?? UUID(),
            stepId: step.id,
            completedAt: Date(),
            note: nil,
        )
        completions.append(completion)
        onStepCompleted(step)
    }
}

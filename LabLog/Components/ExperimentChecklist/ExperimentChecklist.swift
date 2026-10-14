import SwiftUI

/// ★ Custom component.
///
/// Renders an experiment's steps as a vertical timeline and enforces the
/// "can't do Step N+1 before Step N" rule through the injected
/// `StepConstraintEngine`. It never decides locking itself — it asks the engine.
///
/// Properties (inputs):
///   - steps:           the steps to render (sorted by `order` for display)
///   - completions:     two-way bound completion state
///   - recordId:        the lab record new completions belong to
///   - photoStepIds:    steps that currently have a photo attached
///   - photoThumbnails: optional evidence thumbnails shown on their step
///   - isEditable:      false for a submitted record (read-only, taps ignored)
///   - engine:          the constraint engine (unlock logic)
///   - style:           theming (`ChecklistStyle`)
///
/// Events (outputs):
///   - onStepCompleted(Step, StepCompletion)  a step was marked done → persist it;
///                                            successors re-evaluate automatically
///   - onPhotoRequested(Step)                 a requiresPhoto step needs the camera
///   - onLockedStepTapped(Step, String)       user tapped a locked step → reason text
///   - onStepSelected(Step)?                  user tapped a step card → open its guide.
///                                            When nil, a card tap acts like a circle tap.
///
/// Interaction: the status circle is the quick action (complete / photo /
/// explain lock); the card opens the guide. A haptic fires the moment a timer
/// guard runs out and the step becomes available.
///
/// Row states: locked (+reason), available, completed (+time), needs-photo,
/// timer-pending (live countdown ring).
struct ExperimentChecklist: View {
    let steps: [Step]
    @Binding var completions: [StepCompletion]
    let recordId: UUID
    let photoStepIds: Set<UUID>
    var photoThumbnails: [UUID: UIImage] = [:]
    var isEditable: Bool = true
    var engine: StepConstraintEngine = StepConstraintEngine()
    var style: ChecklistStyle = .default

    var onStepCompleted: (Step, StepCompletion) -> Void = { _, _ in }
    var onPhotoRequested: (Step) -> Void = { _ in }
    var onLockedStepTapped: (Step, String) -> Void = { _, _ in }
    var onStepSelected: ((Step) -> Void)? = nil

    /// Drives the warning haptic for taps on locked steps.
    @State private var lockedTapCount = 0
    /// Drives the "time's up" haptic.
    @State private var finishedTimers = 0

    private var orderedSteps: [Step] {
        steps.sorted { $0.order < $1.order }
    }

    private func context(now: Date) -> StepConstraintEngine.Context {
        let times = Dictionary(
            completions.map { ($0.stepId, $0.completedAt) },
            uniquingKeysWith: { first, _ in first },
        )
        return .init(
            completedStepIds: Set(times.keys),
            attachedPhotoStepIds: photoStepIds,
            completionTimes: times,
            now: now,
        )
    }

    /// Only tick every second while a timer guard is actually counting down.
    private var hasRunningTimer: Bool {
        let ctx = context(now: Date())
        return orderedSteps.contains { step in
            guard !ctx.completedStepIds.contains(step.id) else { return false }
            if case .timerPending? = engine.lockReason(for: step, context: ctx) { return true }
            return false
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !hasRunningTimer)) { timeline in
            let ordered = orderedSteps
            VStack(spacing: style.rowSpacing) {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, step in
                    ChecklistRow(
                        step: step,
                        state: rowState(for: step, now: timeline.date),
                        style: style,
                        isLast: index == ordered.count - 1,
                        connectorFilled: completions.contains { $0.stepId == step.id },
                        thumbnail: photoThumbnails[step.id],
                        onNodeTap: { handleTap(step) },
                        onCardTap: onStepSelected.map { select in { select(step) } },
                    )
                }
            }
            .onChange(of: runningTimerIds(now: timeline.date)) { before, after in
                // A timer that just ran out (and wasn't completed) → step is now available.
                if !before.subtracting(after).isEmpty { finishedTimers += 1 }
            }
        }
        .animation(Theme.spring, value: completions)
        .animation(Theme.spring, value: photoStepIds)
        .sensoryFeedback(.success, trigger: completions.count)
        .sensoryFeedback(.warning, trigger: lockedTapCount)
        .sensoryFeedback(.levelChange, trigger: finishedTimers)
    }

    private func runningTimerIds(now: Date) -> Set<UUID> {
        let ctx = context(now: now)
        return Set(orderedSteps.filter { step in
            if case .timerPending? = engine.lockReason(for: step, context: ctx) { return true }
            return false
        }.map(\.id))
    }

    private func rowState(for step: Step, now: Date) -> ChecklistRow.RowState {
        if let completion = completions.first(where: { $0.stepId == step.id }) {
            return .completed(at: completion.completedAt)
        }
        guard let reason = engine.lockReason(for: step, context: context(now: now)) else {
            return .available
        }
        switch reason {
        case .needsPhoto:
            return .needsPhoto
        case .timerPending(let remaining):
            let total = Double(max(step.minDurationSeconds ?? remaining, 1))
            return .timerPending(text: engine.message(for: reason, steps: steps),
                                 progress: 1 - Double(remaining) / total)
        case .prerequisitesIncomplete:
            return .locked(reason: engine.message(for: reason, steps: steps))
        }
    }

    private func handleTap(_ step: Step) {
        guard isEditable, !completions.contains(where: { $0.stepId == step.id }) else { return }

        if let reason = engine.lockReason(for: step, context: context(now: Date())) {
            if case .needsPhoto = reason {
                onPhotoRequested(step)
            } else {
                lockedTapCount += 1
                onLockedStepTapped(step, engine.message(for: reason, steps: steps))
            }
            return
        }

        // Unlocked → complete it; the next render re-evaluates the DAG and
        // unlocks any successors.
        let completion = StepCompletion(
            id: UUID(),
            recordId: recordId,
            stepId: step.id,
            completedAt: Date(),
            note: nil,
        )
        completions.append(completion)
        onStepCompleted(step, completion)
    }
}

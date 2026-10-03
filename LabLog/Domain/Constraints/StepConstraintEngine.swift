import Foundation

/// The single authoritative place that decides whether a step may be unlocked
/// or completed. Pure and unit-testable — views never re-implement this logic.
///
/// Constraint principles enforced here:
///  1. Precedence — a step unlocks only when all its prerequisites are complete
///     (the steps form a dependency DAG).
///  2. Guard conditions — `requiresPhoto` and `minDurationSeconds` preconditions.
///  3. Invariant centralisation — one source of truth, reused by every screen.
struct StepConstraintEngine {

    /// Why a step is currently not actionable (nil == unlocked & completable).
    enum LockReason: Equatable {
        case prerequisitesIncomplete(remaining: [UUID])
        case needsPhoto
        case timerPending(secondsRemaining: Int)
    }

    /// Evaluation inputs for a single step at a point in time.
    struct Context {
        let completedStepIds: Set<UUID>
        let attachedPhotoStepIds: Set<UUID>
        /// When each prerequisite was completed — used for min-duration timers.
        let completionTimes: [UUID: Date]
        let now: Date
    }

    /// Returns the reason a step is locked, or nil if it may be completed now.
    func lockReason(for step: Step, context ctx: Context) -> LockReason? {
        // 1. Precedence: all prerequisites must be complete.
        let missing = step.prerequisiteStepIds.filter { !ctx.completedStepIds.contains($0) }
        if !missing.isEmpty {
            return .prerequisitesIncomplete(remaining: missing)
        }

        // 2. Min-duration timer, measured from the latest prerequisite completion.
        if let minDuration = step.minDurationSeconds {
            let anchor = step.prerequisiteStepIds
                .compactMap { ctx.completionTimes[$0] }
                .max() ?? ctx.now
            let elapsed = ctx.now.timeIntervalSince(anchor)
            let remaining = Int(ceil(Double(minDuration) - elapsed))
            if remaining > 0 {
                return .timerPending(secondsRemaining: remaining)
            }
        }

        // 3. Photo guard.
        if step.requiresPhoto && !ctx.attachedPhotoStepIds.contains(step.id) {
            return .needsPhoto
        }

        return nil
    }

    func isUnlocked(_ step: Step, context ctx: Context) -> Bool {
        lockReason(for: step, context: ctx) == nil
    }

    /// Human-readable message for a locked step, shown inline in the checklist.
    func message(for reason: LockReason, steps: [Step]) -> String {
        switch reason {
        case .prerequisitesIncomplete(let remaining):
            let names = remaining
                .compactMap { id in steps.first { $0.id == id }?.order }
                .sorted()
                .map { "Step \($0)" }
                .joined(separator: ", ")
            return "Complete \(names) first"
        case .needsPhoto:
            return "Attach a photo to complete this step"
        case .timerPending(let secs):
            let m = secs / 60, s = secs % 60
            return String(format: "Wait %d:%02d", m, s)
        }
    }
}

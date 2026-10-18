import Foundation

/// The single authoritative place that decides whether a step may be unlocked
/// or completed. Pure and unit-testable — views never re-implement this logic.
///
/// Constraint principles enforced here:
///  1. Precedence — a step unlocks only when all its prerequisites are complete
///     (the steps form a dependency DAG).
///  2. Guard conditions — `requiresPhoto` and `minDurationSeconds` preconditions.
///  3. Invariant centralisation — one source of truth, reused by every screen.
///  4. Structural validation — a step graph with a cycle or a dangling edge can
///     never be finished, so it is rejected before it reaches a student.
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
        /// When the lab record was started: the wait of a timed step with no
        /// prerequisites runs from here, since that's when the step unlocked.
        var recordStartedAt: Date? = nil
    }

    /// Returns the reason a step is locked, or nil if it may be completed now.
    func lockReason(for step: Step, context ctx: Context) -> LockReason? {
        // 1. Precedence: all prerequisites must be complete.
        let missing = step.prerequisiteStepIds.filter { !ctx.completedStepIds.contains($0) }
        if !missing.isEmpty {
            return .prerequisitesIncomplete(remaining: missing)
        }

        // 2. Min-duration timer, measured from when the step unlocked: the latest
        //    prerequisite completion, or the record's start for a step with none.
        //    (Anchoring on `now` would restart the wait on every check: failure 028.)
        if let minDuration = step.minDurationSeconds {
            let anchor = step.prerequisiteStepIds
                .compactMap { ctx.completionTimes[$0] }
                .max() ?? ctx.recordStartedAt ?? ctx.now
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

    /// Steps not yet completed whose prerequisites are all met — what the
    /// student can work on next (guards may still apply).
    func reachableSteps(_ steps: [Step], context ctx: Context) -> [Step] {
        steps
            .filter { !ctx.completedStepIds.contains($0.id) }
            .filter { step in step.prerequisiteStepIds.allSatisfy(ctx.completedStepIds.contains) }
            .sorted { $0.order < $1.order }
    }

    /// True when every step in the experiment has been completed.
    func isComplete(_ steps: [Step], completedStepIds: Set<UUID>) -> Bool {
        !steps.isEmpty && steps.allSatisfy { completedStepIds.contains($0.id) }
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

    // MARK: - Graph validation

    /// Structural problems in an experiment's step graph.
    enum GraphIssue: Equatable {
        case selfDependency(step: UUID)
        case unknownPrerequisite(step: UUID, missing: UUID)
        /// Steps that can never become ready because they sit on (or behind) a cycle.
        case cycle(steps: [UUID])
    }

    /// Kahn's algorithm: repeatedly take a step whose prerequisites are all
    /// placed (lowest `order` first, so the result is deterministic). Returns a
    /// valid completion order, or nil when a cycle leaves steps unplaced.
    func topologicalOrder(_ steps: [Step]) -> [Step]? {
        let (ordered, stuck) = kahn(steps)
        return stuck.isEmpty ? ordered : nil
    }

    /// Every structural issue in the graph; empty means the experiment is completable.
    func validate(_ steps: [Step]) -> [GraphIssue] {
        let known = Set(steps.map(\.id))
        var issues: [GraphIssue] = []
        for step in steps.sorted(by: { $0.order < $1.order }) {
            for prereq in step.prerequisiteStepIds {
                if prereq == step.id {
                    issues.append(.selfDependency(step: step.id))
                } else if !known.contains(prereq) {
                    issues.append(.unknownPrerequisite(step: step.id, missing: prereq))
                }
            }
        }
        let stuck = kahn(steps).stuck
        if !stuck.isEmpty {
            issues.append(.cycle(steps: stuck.map(\.id)))
        }
        return issues
    }

    private func kahn(_ steps: [Step]) -> (ordered: [Step], stuck: [Step]) {
        let known = Set(steps.map(\.id))
        // Unknown prerequisites are reported by `validate`; they don't block ordering.
        var unmet: [UUID: Set<UUID>] = [:]
        for step in steps {
            unmet[step.id] = Set(step.prerequisiteStepIds).intersection(known)
        }

        var ready = steps.filter { unmet[$0.id]?.isEmpty == true }
        var ordered: [Step] = []
        var placed: Set<UUID> = []

        while !ready.isEmpty {
            ready.sort { $0.order < $1.order }
            let next = ready.removeFirst()
            guard placed.insert(next.id).inserted else { continue }
            ordered.append(next)
            for step in steps where unmet[step.id]?.contains(next.id) == true {
                unmet[step.id]?.remove(next.id)
                if unmet[step.id]?.isEmpty == true { ready.append(step) }
            }
        }

        let stuck = steps
            .filter { !placed.contains($0.id) }
            .sorted { $0.order < $1.order }
        return (ordered, stuck)
    }
}

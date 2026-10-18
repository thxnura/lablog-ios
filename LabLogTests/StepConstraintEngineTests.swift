import XCTest
@testable import LabLog

/// Unit tests for the constraint centrepiece. Demonstrates precedence, photo,
/// and timer guards — the core of the app's constraint design.
final class StepConstraintEngineTests: XCTestCase {
    let engine = StepConstraintEngine()
    let exp = UUID()

    private func step(_ order: Int, prereqs: [UUID] = [], photo: Bool = false, timer: Int? = nil, id: UUID = UUID()) -> Step {
        Step(id: id, experimentId: exp, order: order, title: "Step \(order)",
             instruction: nil, requiresPhoto: photo, minDurationSeconds: timer,
             prerequisiteStepIds: prereqs)
    }

    private func context(completed: Set<UUID> = [], photos: Set<UUID> = [],
                         times: [UUID: Date] = [:], now: Date = Date()) -> StepConstraintEngine.Context {
        .init(completedStepIds: completed, attachedPhotoStepIds: photos,
              completionTimes: times, now: now)
    }

    // MARK: Guards

    func testStep4LockedUntilStep3Complete() {
        let s3 = step(3)
        let s4 = step(4, prereqs: [s3.id])
        XCTAssertFalse(engine.isUnlocked(s4, context: context()))
        XCTAssertTrue(engine.isUnlocked(s4, context: context(completed: [s3.id])))
    }

    func testPhotoGuardBlocksCompletion() {
        let s = step(1, photo: true)
        XCTAssertEqual(engine.lockReason(for: s, context: context()), .needsPhoto)
        XCTAssertTrue(engine.isUnlocked(s, context: context(photos: [s.id])))
    }

    func testTimerGuardCountsDown() {
        let prereq = step(1)
        let timed = step(2, prereqs: [prereq.id], timer: 300)
        let now = Date()
        let justStarted = context(completed: [prereq.id], times: [prereq.id: now], now: now)
        if case .timerPending(let secs)? = engine.lockReason(for: timed, context: justStarted) {
            XCTAssertEqual(secs, 300, accuracy: 1)
        } else {
            XCTFail("expected timerPending")
        }
        let later = context(completed: [prereq.id], times: [prereq.id: now],
                            now: now.addingTimeInterval(301))
        XCTAssertTrue(engine.isUnlocked(timed, context: later))
    }

    /// A step with two parents (a join in the DAG) needs BOTH.
    func testMultiplePrerequisitesMustAllBeComplete() {
        let a = step(1), b = step(2)
        let join = step(3, prereqs: [a.id, b.id])
        XCTAssertEqual(engine.lockReason(for: join, context: context(completed: [a.id])),
                       .prerequisitesIncomplete(remaining: [b.id]))
        XCTAssertTrue(engine.isUnlocked(join, context: context(completed: [a.id, b.id])))
    }

    /// Precedence is checked before guards, so the student is told the real blocker.
    func testPrerequisiteReportedBeforePhotoGuard() {
        let a = step(1)
        let b = step(2, prereqs: [a.id], photo: true)
        XCTAssertEqual(engine.lockReason(for: b, context: context()),
                       .prerequisitesIncomplete(remaining: [a.id]))
    }

    func testTimerAnchorsOnLatestPrerequisite() {
        let a = step(1), b = step(2)
        let timed = step(3, prereqs: [a.id, b.id], timer: 60)
        let t0 = Date()
        let ctx = context(completed: [a.id, b.id],
                          times: [a.id: t0, b.id: t0.addingTimeInterval(50)],
                          now: t0.addingTimeInterval(70))
        // 70 s after a, but only 20 s after b → 40 s left.
        XCTAssertEqual(engine.lockReason(for: timed, context: ctx), .timerPending(secondsRemaining: 40))
    }

    func testLockMessages() {
        let a = step(1), b = step(2)
        let steps = [a, b, step(3, prereqs: [a.id, b.id])]
        XCTAssertEqual(engine.message(for: .prerequisitesIncomplete(remaining: [b.id, a.id]), steps: steps),
                       "Complete Step 1, Step 2 first")
        XCTAssertEqual(engine.message(for: .timerPending(secondsRemaining: 150), steps: steps), "Wait 2:30")
        XCTAssertEqual(engine.message(for: .needsPhoto, steps: steps), "Attach a photo to complete this step")
    }

    func testReachableStepsAndCompletion() {
        let a = step(1), b = step(2)
        let c = step(3, prereqs: [a.id, b.id])
        let steps = [c, b, a]
        XCTAssertEqual(engine.reachableSteps(steps, context: context()).map(\.order), [1, 2])
        XCTAssertEqual(engine.reachableSteps(steps, context: context(completed: [a.id, b.id])).map(\.order), [3])
        XCTAssertFalse(engine.isComplete(steps, completedStepIds: [a.id, b.id]))
        XCTAssertTrue(engine.isComplete(steps, completedStepIds: [a.id, b.id, c.id]))
        XCTAssertFalse(engine.isComplete([], completedStepIds: []))
    }

    // MARK: Graph validation

    func testTopologicalOrderRespectsPrecedence() {
        let a = step(3), b = step(1, prereqs: [a.id]), c = step(2)
        let order = engine.topologicalOrder([a, b, c])?.map(\.order)
        // 1 depends on 3, so 3 must come before it; ties break by `order`.
        XCTAssertEqual(order, [2, 3, 1])
    }

    func testCycleIsDetected() {
        let idA = UUID(), idB = UUID()
        let a = step(1, prereqs: [idB], id: idA)
        let b = step(2, prereqs: [idA], id: idB)
        let free = step(3)
        XCTAssertNil(engine.topologicalOrder([a, b, free]))
        XCTAssertEqual(engine.validate([a, b, free]), [.cycle(steps: [idA, idB])])
    }

    func testDanglingAndSelfEdgesAreReported() {
        let ghost = UUID()
        let selfId = UUID()
        let a = step(1, prereqs: [ghost])
        let s = step(2, prereqs: [selfId], id: selfId)
        let issues = engine.validate([a, s])
        XCTAssertTrue(issues.contains(.unknownPrerequisite(step: a.id, missing: ghost)))
        XCTAssertTrue(issues.contains(.selfDependency(step: selfId)))
    }

    func testBundledCatalogIsValid() {
        for experiment in CatalogSeed.experiments {
            let steps = CatalogSeed.steps.filter { $0.experimentId == experiment.id }
            XCTAssertFalse(steps.isEmpty, experiment.title)
            XCTAssertEqual(engine.validate(steps), [], experiment.title)
        }
    }
}

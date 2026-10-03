import XCTest
@testable import LabLog

/// Unit tests for the constraint centrepiece. Demonstrates precedence, photo,
/// and timer guards — good evidence for the "constraint design" grading line.
final class StepConstraintEngineTests: XCTestCase {
    let engine = StepConstraintEngine()
    let exp = UUID()

    private func step(_ order: Int, prereqs: [UUID] = [], photo: Bool = false, timer: Int? = nil) -> Step {
        Step(id: UUID(), experimentId: exp, order: order, title: "Step \(order)",
             instruction: nil, requiresPhoto: photo, minDurationSeconds: timer,
             prerequisiteStepIds: prereqs)
    }

    private func context(completed: Set<UUID> = [], photos: Set<UUID> = [],
                         times: [UUID: Date] = [:], now: Date = Date()) -> StepConstraintEngine.Context {
        .init(completedStepIds: completed, attachedPhotoStepIds: photos,
              completionTimes: times, now: now)
    }

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
}

import XCTest
@testable import LabLog

/// Which step drives the Dynamic Island timer, deep links from it, and the
/// step-guide catalog upgrade.
@MainActor
final class LiveActivityAndGuideTests: XCTestCase {
    private let exp = UUID()

    private func step(_ order: Int, prereqs: [UUID] = [], timer: Int? = nil) -> Step {
        Step(id: UUID(), experimentId: exp, order: order, title: "Step \(order)", instruction: nil,
             requiresPhoto: false, minDurationSeconds: timer, prerequisiteStepIds: prereqs)
    }

    private func done(_ step: Step, at date: Date) -> StepCompletion {
        StepCompletion(id: UUID(), recordId: UUID(), stepId: step.id, completedAt: date)
    }

    // MARK: Timed step

    func testNoTimerUntilPrerequisitesAreDone() {
        let a = step(1), b = step(2, prereqs: [a.id], timer: 300)
        XCTAssertNil(StepTimerCoordinator.timedStep(steps: [a, b], completions: []))
    }

    func testTimerAnchorsOnLatestPrerequisite() {
        let a = step(1), b = step(2)
        let timed = step(3, prereqs: [a.id, b.id], timer: 60)
        let t0 = Date(timeIntervalSince1970: 1_000)
        let result = StepTimerCoordinator.timedStep(steps: [a, b, timed],
                                                    completions: [done(a, at: t0), done(b, at: t0.addingTimeInterval(20))])
        XCTAssertEqual(result?.step.id, timed.id)
        XCTAssertEqual(result?.start, t0.addingTimeInterval(20))
        XCTAssertEqual(result?.end, t0.addingTimeInterval(80))
    }

    func testTimerGoneOnceStepCompleted() {
        let a = step(1), b = step(2, prereqs: [a.id], timer: 30)
        let now = Date()
        XCTAssertNil(StepTimerCoordinator.timedStep(steps: [a, b], completions: [done(a, at: now), done(b, at: now)]))
    }

    // MARK: Deep links

    func testDeepLinkParsing() {
        let record = UUID(), stepId = UUID()
        let link = LabLogDeepLink(url: URL(string: "lablog://record/\(record.uuidString)?step=\(stepId.uuidString)")!)
        XCTAssertEqual(link?.recordId, record)
        XCTAssertEqual(link?.stepId, stepId)
        XCTAssertNil(LabLogDeepLink(url: URL(string: "https://record/\(record.uuidString)")!))
        XCTAssertNil(LabLogDeepLink(url: URL(string: "lablog://record/not-a-uuid")!))
        XCTAssertNil(LabLogDeepLink(url: URL(string: "lablog://record/\(record.uuidString)")!)?.stepId)
    }

    func testAttributesDeepLinkRoundTrips() {
        let attributes = StepTimerAttributes(recordId: UUID(), stepId: UUID(), stepOrder: 3, stepTitle: "Time 20 oscillations",
                                             experimentTitle: "Simple Pendulum", labCode: "PHYS101", labName: "Physics Lab",
                                             totalSteps: 4, nextStepTitle: "Repeat at two more lengths")
        let link = LabLogDeepLink(url: attributes.deepLink)
        XCTAssertEqual(link?.recordId, attributes.recordId)
        XCTAssertEqual(link?.stepId, attributes.stepId)
    }

    // MARK: Guides

    func testEveryBundledStepHasAGuide() {
        for step in CatalogSeed.steps {
            XCTAssertFalse(step.guide?.steps.isEmpty ?? true, "\(step.title) has no guide")
            XCTAssertNotNil(step.guide?.expected, step.title)
        }
    }

    /// A device that cached the v1 catalog (no guides) gets them on upgrade.
    func testOlderBundledCatalogIsUpgraded() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "LabLogTests-\(UUID().uuidString)"))
        let store = SwiftDataStore(container: try SwiftDataStore.makeContainer(inMemory: true))
        let v1Steps = CatalogSeed.steps.map { step -> Step in var s = step; s.guide = nil; return s }
        store.replaceCatalog(labs: CatalogSeed.labs, experiments: CatalogSeed.experiments, steps: v1Steps)
        defaults.set(1, forKey: "bundledCatalogVersion")
        XCTAssertNil(store.steps(experimentId: CatalogSeed.pendulum.id).first?.guide)

        CatalogSeed.installIfNeeded(into: store, defaults: defaults)

        XCTAssertNotNil(store.steps(experimentId: CatalogSeed.pendulum.id).first?.guide)
        XCTAssertEqual(defaults.integer(forKey: "bundledCatalogVersion"), CatalogSeed.version)
    }

    func testGuideDecodesFromServerJSON() throws {
        let json = """
        {"id":"33333333-0000-0000-0002-000000000001","experimentId":"22222222-2222-2222-2222-222222222224",
         "order":1,"title":"Measure","instruction":null,"requiresPhoto":false,"minDurationSeconds":null,
         "prerequisiteStepIds":[],"guide":{"steps":["a","b"],"safety":null,"expected":"c"}}
        """
        let step = try JSONDecoder().decode(Step.self, from: Data(json.utf8))
        XCTAssertEqual(step.guide?.steps, ["a", "b"])
        let old = try JSONDecoder().decode(Step.self, from: Data(json.replacingOccurrences(of: #","guide":{"steps":["a","b"],"safety":null,"expected":"c"}"#, with: "").utf8))
        XCTAssertNil(old.guide, "catalogs without guides still decode")
    }
}

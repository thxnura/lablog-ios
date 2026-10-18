import XCTest
@testable import LabLog

/// A lecturer's new experiment (ADR-029): what it sends, and what stops it.
final class ExperimentDraftTests: XCTestCase {
    private func draft() -> ExperimentDraft {
        var draft = ExperimentDraft()
        draft.title = "Heating test"
        draft.steps = [
            .init(title: "Weigh the sample"),
            .init(title: "Heat for two minutes", waitSeconds: 120, after: [1]),
            .init(title: "Photograph the result", requiresPhoto: true, after: [1, 2]),
        ]
        return draft
    }

    func testRequestCarriesStepsAndRulesByNumber() {
        let request = draft().request
        XCTAssertEqual(request.title, "Heating test")
        XCTAssertEqual(request.steps.map(\.prerequisites), [[], [1], [1, 2]])
        XCTAssertEqual(request.steps[1].minDurationSeconds, 120)
        XCTAssertEqual(request.steps.map(\.requiresPhoto), [false, false, true])
        XCTAssertTrue(draft().problems.isEmpty)
    }

    func testRemovingAStepRenumbersTheRules() {
        var d = draft()
        d.removeStep(at: 0) // "Weigh the sample" goes; 2 → 1, 3 → 2
        XCTAssertEqual(d.steps.map(\.after), [[], [1]])
        XCTAssertEqual(ExperimentDraft.summary(of: d.steps[1]), "Photo · After 1")
    }

    /// Editing starts from the catalog and sends each existing step's id back,
    /// so students' work on it stays attached; rules come back as step numbers.
    func testEditingAnExistingExperimentKeepsStepIds() {
        let experiment = Experiment(id: UUID(), labId: UUID(), title: "Titration", description: nil)
        let first = Step(id: UUID(), experimentId: experiment.id, order: 1, title: "Rinse", instruction: nil,
                         requiresPhoto: false, minDurationSeconds: nil, prerequisiteStepIds: [])
        let second = Step(id: UUID(), experimentId: experiment.id, order: 2, title: "Wait", instruction: nil,
                          requiresPhoto: false, minDurationSeconds: 45, prerequisiteStepIds: [first.id])
        var d = ExperimentDraft(experiment: experiment, steps: [second, first])
        d.steps.append(.init(title: "New step", after: [2]))

        let request = d.request
        XCTAssertEqual(request.steps.map(\.id), [first.id, second.id, nil])
        XCTAssertEqual(request.steps.map(\.prerequisites), [[], [1], [2]])
        XCTAssertTrue(ExperimentDraft.waitChoices(including: 45).contains(45), "an odd wait stays selectable")
        XCTAssertEqual(ExperimentDraft.formatWait(90), "1 min 30 s")
    }

    func testProblemsBlockSaving() {
        var d = ExperimentDraft()
        XCTAssertEqual(d.problems, ["Give the experiment a title.", "Add at least one step."])
        d.title = "Loop"
        d.steps = [.init(title: "A", after: [2]), .init(title: "B", after: [1])]
        XCTAssertTrue(d.problems.contains("The step order has a loop or a missing step."),
                      "the same constraint engine that checks every catalog")
    }
}

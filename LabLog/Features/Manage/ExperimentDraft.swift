import Foundation

/// A lecturer's new experiment before it is sent (ADR-029). Steps are
/// numbered by position, and a step can only depend on earlier ones, so the
/// graph can't loop by construction; it is still checked with the same
/// `StepConstraintEngine.validate` that guards the catalog, and again with
/// Kahn's algorithm on the server.
struct ExperimentDraft: Equatable {
    struct StepDraft: Identifiable, Equatable {
        let id = UUID()
        /// The step's id on the server when editing an existing experiment.
        var serverId: UUID?
        var title = ""
        var instruction = ""
        var requiresPhoto = false
        /// Seconds the student must wait before marking the step done.
        var waitSeconds: Int?
        /// Numbers (1-based) of the earlier steps that must be done first.
        var after: Set<Int> = []
    }

    var title = ""
    var description = ""
    var steps: [StepDraft] = []

    init() {}

    /// An existing experiment, to edit: its steps by order, rules as step numbers.
    init(experiment: Experiment, steps: [Step]) {
        title = experiment.title
        description = experiment.description ?? ""
        let ordered = steps.sorted { $0.order < $1.order }
        let number = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($1.id, $0 + 1) })
        self.steps = ordered.map { step in
            StepDraft(serverId: step.id, title: step.title, instruction: step.instruction ?? "",
                      requiresPhoto: step.requiresPhoto, waitSeconds: step.minDurationSeconds,
                      after: Set(step.prerequisiteStepIds.compactMap { number[$0] }))
        }
    }

    /// The wait times a lecturer can pick, in seconds.
    static let waitChoices = [30, 60, 120, 300, 600, 900, 1800]

    /// Removes a step; later steps move up a number and their "after" lists follow.
    mutating func removeStep(at index: Int) {
        let removed = index + 1
        steps.remove(at: index)
        for i in steps.indices {
            steps[i].after = Set(steps[i].after.compactMap { n in
                n == removed ? nil : (n > removed ? n - 1 : n)
            })
        }
    }

    /// What still stops the draft from being saved; empty when it's ready.
    var problems: [String] {
        var problems: [String] = []
        if title.trimmingCharacters(in: .whitespaces).count < 2 { problems.append("Give the experiment a title.") }
        if steps.isEmpty { problems.append("Add at least one step.") }
        for (index, step) in steps.enumerated() where step.title.trimmingCharacters(in: .whitespaces).isEmpty {
            problems.append("Step \(index + 1) needs a title.")
        }
        // The same check the app runs on every catalog it downloads.
        let issues = StepConstraintEngine().validate(previewSteps)
        if !issues.isEmpty { problems.append("The step order has a loop or a missing step.") }
        return problems
    }

    /// The steps as the constraint engine sees them (temporary ids).
    var previewSteps: [Step] {
        let experimentId = UUID()
        let ids = steps.map(\.id)
        return steps.enumerated().map { index, step in
            Step(id: step.id, experimentId: experimentId, order: index + 1, title: step.title,
                 instruction: step.instruction.isEmpty ? nil : step.instruction,
                 requiresPhoto: step.requiresPhoto, minDurationSeconds: step.waitSeconds,
                 prerequisiteStepIds: step.after.sorted().compactMap { n in ids.indices.contains(n - 1) ? ids[n - 1] : UUID() })
        }
    }

    var request: NewExperimentDTO {
        NewExperimentDTO(
            title: title.trimmingCharacters(in: .whitespaces),
            description: description.trimmingCharacters(in: .whitespaces).isEmpty ? nil : description,
            steps: steps.map { step in
                NewExperimentDTO.NewStep(
                    id: step.serverId,
                    title: step.title.trimmingCharacters(in: .whitespaces),
                    instruction: step.instruction.trimmingCharacters(in: .whitespaces).isEmpty ? nil : step.instruction,
                    requiresPhoto: step.requiresPhoto,
                    minDurationSeconds: step.waitSeconds,
                    prerequisites: step.after.sorted())
            })
    }

    /// "Photo · Wait 2 min · After 1, 2" for a step row.
    static func summary(of step: StepDraft) -> String {
        var parts: [String] = []
        if step.requiresPhoto { parts.append("Photo") }
        if let wait = step.waitSeconds { parts.append("Wait \(formatWait(wait))") }
        if !step.after.isEmpty { parts.append("After \(step.after.sorted().map(String.init).joined(separator: ", "))") }
        return parts.isEmpty ? "No conditions" : parts.joined(separator: " · ")
    }

    static func formatWait(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) s" }
        return seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds / 60) min \(seconds % 60) s"
    }

    /// The picker's choices, plus a step's own wait if it isn't one of them.
    static func waitChoices(including current: Int?) -> [Int] {
        guard let current, !waitChoices.contains(current) else { return waitChoices }
        return (waitChoices + [current]).sorted()
    }
}

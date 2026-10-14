import AppIntents
import Foundation

/// The "Mark done" button in the Live Activity. Live Activity intents run in
/// the app's process, so the work is handed to the app through
/// `LiveActivityBridge` — the widget extension compiles this file but never
/// performs it. The app still checks the step with StepConstraintEngine, so a
/// press before the wait is over does nothing.
struct CompleteTimedStepIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark step done"
    static let description = IntentDescription("Completes a timed lab step once its waiting time is over.")
    static let isDiscoverable = false

    @Parameter(title: "Record") var recordId: String
    @Parameter(title: "Step") var stepId: String

    init() {}

    init(recordId: UUID, stepId: UUID) {
        self.recordId = recordId.uuidString
        self.stepId = stepId.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let record = UUID(uuidString: recordId), let step = UUID(uuidString: stepId),
           let complete = await LiveActivityBridge.completeStep {
            _ = await complete(record, step)
        }
        return .result()
    }
}

/// Hook the app installs at launch so Live Activity buttons can reach the store.
enum LiveActivityBridge {
    @MainActor static var completeStep: (@MainActor (UUID, UUID) async -> Bool)?
}

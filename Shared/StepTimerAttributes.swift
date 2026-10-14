import ActivityKit
import Foundation

/// Live Activity payload for a timed lab step (a `minDurationSeconds` guard).
/// Shared by the app (which starts/ends the activity) and the widget extension
/// (which draws it in the Dynamic Island and on the Lock Screen).
struct StepTimerAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the wait began (the latest prerequisite's completion time).
        var startDate: Date
        /// When the step becomes completable.
        var endDate: Date
        /// Set once the step has been marked done (shown briefly before dismissal).
        var isCompleted: Bool = false
        /// Steps finished in this record so far (drives the progress dots).
        var completedSteps: Int = 0

        var range: ClosedRange<Date> { startDate...max(endDate, startDate.addingTimeInterval(1)) }
    }

    let recordId: UUID
    let stepId: UUID
    let stepOrder: Int
    let stepTitle: String
    let experimentTitle: String
    let labCode: String
    let labName: String
    let totalSteps: Int
    /// The step that unlocks after this one, for the "Up next" line.
    let nextStepTitle: String?

    /// Opens the record with this step's guide.
    var deepLink: URL {
        URL(string: "lablog://record/\(recordId.uuidString)?step=\(stepId.uuidString)")!
    }
}

/// Parsed `lablog://record/<recordId>?step=<stepId>` link (Live Activity,
/// notification tap).
struct LabLogDeepLink: Equatable {
    let recordId: UUID
    let stepId: UUID?

    init?(url: URL) {
        guard url.scheme == "lablog", url.host() == "record",
              let id = UUID(uuidString: url.lastPathComponent) else { return nil }
        recordId = id
        let step = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "step" }?.value
        stepId = step.flatMap(UUID.init(uuidString:))
    }
}

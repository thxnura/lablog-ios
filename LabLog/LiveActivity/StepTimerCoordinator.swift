import ActivityKit
import Foundation
import OSLog
import UserNotifications

/// Keeps the Dynamic Island in step with the checklist. When a timed step's
/// prerequisites are done, its wait begins: start a Live Activity and schedule
/// a "ready" notification. When the step is completed (in the app or from the
/// island's button) or the record is submitted, end both.
///
/// Which step is waiting is decided by the same rules as the checklist:
/// all prerequisites complete + `minDurationSeconds`, anchored on the latest
/// prerequisite completion (see StepConstraintEngine).
@MainActor
final class StepTimerCoordinator {
    private let logger = Logger(subsystem: "com.thxnura.LabLog", category: "live-activity")
    private let notifications = UNUserNotificationCenter.current()
    private var askedForNotifications = false

    struct TimedStep: Equatable {
        let step: Step
        let start: Date
        let end: Date
    }

    /// The timed step currently waiting (or ready) in a record, if any.
    static func timedStep(steps: [Step], completions: [StepCompletion]) -> TimedStep? {
        let done = Dictionary(completions.map { ($0.stepId, $0.completedAt) }, uniquingKeysWith: { a, _ in a })
        return steps
            .sorted { $0.order < $1.order }
            .compactMap { step -> TimedStep? in
                guard let seconds = step.minDurationSeconds, done[step.id] == nil,
                      step.prerequisiteStepIds.allSatisfy({ done[$0] != nil }) else { return nil }
                let start = step.prerequisiteStepIds.compactMap { done[$0] }.max() ?? Date()
                return TimedStep(step: step, start: start, end: start.addingTimeInterval(TimeInterval(seconds)))
            }
            .first
    }

    /// Reconcile the Live Activity + notification for one record.
    func refresh(record: LabRecord, experiment: Experiment, lab: Lab?,
                 steps: [Step], completions: [StepCompletion]) {
        let current = Activity<StepTimerAttributes>.activities.filter { $0.attributes.recordId == record.id }
        let timed = record.status == .draft ? Self.timedStep(steps: steps, completions: completions) : nil

        // End anything that no longer matches the waiting step.
        for activity in current where activity.attributes.stepId != timed?.step.id {
            end(activity, completed: completions.contains { $0.stepId == activity.attributes.stepId })
            notifications.removePendingNotificationRequests(
                withIdentifiers: [notificationId(record.id, activity.attributes.stepId)])
        }
        guard let timed else { return }
        if let running = current.first(where: { $0.attributes.stepId == timed.step.id }) {
            // Same wait still running; keep its progress dots current.
            if running.content.state.completedSteps != completions.count {
                var state = running.content.state
                state.completedSteps = completions.count
                Task { await running.update(ActivityContent(state: state, staleDate: timed.end)) }
            }
            return
        }

        let next = steps
            .filter { $0.prerequisiteStepIds.contains(timed.step.id) }
            .min { $0.order < $1.order }
        start(timed, record: record, experiment: experiment, lab: lab,
              totalSteps: steps.count, completedSteps: completions.count, nextStepTitle: next?.title)
        scheduleReadyNotification(for: timed, record: record)
    }

    /// A fresh start (UI tests launch with an empty in-memory store): drop timers
    /// and "ready" notifications left over from an earlier run.
    static func clearAll() {
        for activity in Activity<StepTimerAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    static func activeRecordIds() -> [UUID] {
        Activity<StepTimerAttributes>.activities.map(\.attributes.recordId)
    }

    /// Clean up after the step is completed from anywhere.
    func stepCompleted(recordId: UUID, stepId: UUID) {
        for activity in Activity<StepTimerAttributes>.activities
        where activity.attributes.recordId == recordId && activity.attributes.stepId == stepId {
            end(activity, completed: true)
        }
        notifications.removePendingNotificationRequests(withIdentifiers: [notificationId(recordId, stepId)])
    }

    /// The record was discarded: stop its timer and its "ready" notifications.
    func endAll(recordId: UUID) {
        for activity in Activity<StepTimerAttributes>.activities where activity.attributes.recordId == recordId {
            end(activity, completed: false)
        }
        notifications.getPendingNotificationRequests { [notifications] requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix("step-ready-\(recordId.uuidString)-") }
            notifications.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    // MARK: Private

    private func start(_ timed: TimedStep, record: LabRecord, experiment: Experiment, lab: Lab?,
                       totalSteps: Int, completedSteps: Int, nextStepTitle: String?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.info("Live Activities are disabled; skipping")
            return
        }
        let attributes = StepTimerAttributes(
            recordId: record.id, stepId: timed.step.id, stepOrder: timed.step.order,
            stepTitle: timed.step.title, experimentTitle: experiment.title,
            labCode: lab?.code ?? "", labName: lab?.name ?? "",
            totalSteps: totalSteps, nextStepTitle: nextStepTitle,
        )
        let state = StepTimerAttributes.ContentState(startDate: timed.start, endDate: timed.end,
                                                     completedSteps: completedSteps)
        do {
            _ = try Activity.request(attributes: attributes,
                                     content: ActivityContent(state: state, staleDate: timed.end),
                                     pushType: nil)
        } catch {
            logger.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func end(_ activity: Activity<StepTimerAttributes>, completed: Bool) {
        var state = activity.content.state
        state.isCompleted = completed
        Task {
            await activity.end(ActivityContent(state: state, staleDate: nil),
                               dismissalPolicy: completed ? .after(Date().addingTimeInterval(4)) : .immediate)
        }
    }

    private func notificationId(_ recordId: UUID, _ stepId: UUID) -> String {
        "step-ready-\(recordId.uuidString)-\(stepId.uuidString)"
    }

    /// Asked for at the moment it's useful (the first timer), not at launch.
    private func scheduleReadyNotification(for timed: TimedStep, record: LabRecord) {
        let interval = timed.end.timeIntervalSinceNow
        guard interval > 1 else { return }
        let id = notificationId(record.id, timed.step.id)
        Task {
            if !askedForNotifications {
                askedForNotifications = true
                _ = try? await notifications.requestAuthorization(options: [.alert, .sound])
            }
            let content = UNMutableNotificationContent()
            content.title = "Step \(timed.step.order) is ready"
            content.body = "\(timed.step.title): the wait is over. You can mark it done."
            content.sound = .default
            content.userInfo = ["url": "lablog://record/\(record.id.uuidString)?step=\(timed.step.id.uuidString)"]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            try? await notifications.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}

/// Routes notification taps to the deep-link handler and shows "ready"
/// banners even while the app is open.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    var onOpenURL: (URL) -> Void = { _ in }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        guard let link = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: link) else { return }
        await MainActor.run { onOpenURL(url) }
    }
}

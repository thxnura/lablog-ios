import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Dynamic Island + Lock Screen presentation of a running step timer.
///
/// The countdown, ring and bar are drawn by the system from the date range, so
/// they stay live without the app running. `isStale` flips at the end date
/// (the activity's staleDate) and every presentation switches to "Ready".
struct StepTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: StepTimerAttributes.self) { context in
            LockScreenTimerView(context: context)
                .activityBackgroundTint(Color(white: 0.08).opacity(0.82))
                .activitySystemActionForegroundColor(.white)
                .widgetURL(context.attributes.deepLink)
        } dynamicIsland: { context in
            let look = TimerLook(context: context)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DisciplineTile(discipline: look.discipline, size: 46)
                        .padding(.leading, 6)
                        .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 1) {
                        CountdownText(state: context.state, ready: look.ready)
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundStyle(look.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(look.ready ? "READY" : "LEFT")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.5))
                            .fixedSize()
                    }
                    .frame(minWidth: 64, alignment: .trailing)
                    .padding(.trailing, 6)
                    .padding(.top, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(context.attributes.labCode) · STEP \(context.attributes.stepOrder) OF \(context.attributes.totalSteps)")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(look.discipline.tint)
                        Text(context.attributes.stepTitle)
                            .font(.system(.headline, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        ProgressView(timerInterval: context.state.range, countsDown: false) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .tint(look.accent)
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                StepDots(total: context.attributes.totalSteps,
                                         completed: context.state.completedSteps,
                                         tint: look.discipline.tint)
                                Text(look.ready ? "Wait complete" : "Ready \(context.state.endDate.formatted(date: .omitted, time: .shortened))")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(look.ready ? .green : .white.opacity(0.6))
                            }
                            Spacer(minLength: 6)
                            Link(destination: context.attributes.deepLink) {
                                Image(systemName: "text.book.closed.fill")
                                    .font(.caption.weight(.semibold))
                                    .frame(width: 32, height: 32)
                                    .background(.white.opacity(0.14), in: Circle())
                                    .foregroundStyle(.white)
                            }
                            .accessibilityLabel("Open step guide")
                            MarkDoneButton(attributes: context.attributes, ready: look.ready, tint: look.discipline.tint)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 4)
                }
            } compactLeading: {
                ZStack {
                    if look.ready {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        ProgressView(timerInterval: context.state.range, countsDown: true) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .progressViewStyle(.circular)
                        .tint(look.discipline.tint)
                        Image(systemName: look.discipline.symbol)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(look.discipline.tint)
                    }
                }
                .frame(width: 22, height: 22)
                .padding(.leading, 2)
            } compactTrailing: {
                CountdownText(state: context.state, ready: look.ready)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(look.accent)
                    .frame(maxWidth: 50, alignment: .trailing)
            } minimal: {
                if look.ready {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    ProgressView(timerInterval: context.state.range, countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        Image(systemName: "hourglass")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .progressViewStyle(.circular)
                    .tint(look.discipline.tint)
                }
            }
            .widgetURL(context.attributes.deepLink)
            .keylineTint(look.discipline.tint)
        }
    }
}

/// Derived appearance shared by every presentation.
private struct TimerLook {
    let discipline: Discipline
    let ready: Bool
    var accent: Color { ready ? .green : discipline.tint }

    init(context: ActivityViewContext<StepTimerAttributes>) {
        discipline = .of(labCode: context.attributes.labCode)
        ready = context.isStale || context.state.isCompleted
    }
}

// MARK: - Pieces

private struct DisciplineTile: View {
    let discipline: Discipline
    var size: CGFloat

    var body: some View {
        Image(systemName: discipline.symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(discipline.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Live countdown that becomes "Ready" (or "Done") when the wait is over.
private struct CountdownText: View {
    let state: StepTimerAttributes.ContentState
    let ready: Bool

    var body: some View {
        if ready {
            Text(state.isCompleted ? "Done" : "Ready")
        } else {
            Text(timerInterval: state.range, countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Elapsed-time bar with the start and ready times underneath.
private struct TimeBar: View {
    let state: StepTimerAttributes.ContentState
    let accent: Color
    let ready: Bool

    var body: some View {
        VStack(spacing: 5) {
            ProgressView(timerInterval: state.range, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(accent)
            HStack {
                Text("Started \(state.startDate.formatted(date: .omitted, time: .shortened))")
                Spacer()
                Text(ready ? "You can mark it done" : "Ready at \(state.endDate.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(ready ? .green : .white.opacity(0.75))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
        }
    }
}

/// One capsule per step: done, current, still to come.
private struct StepDots: View {
    let total: Int
    let completed: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(color(for: index))
                    .frame(width: index == completed ? 14 : 7, height: 5)
            }
        }
        .accessibilityLabel("\(completed) of \(total) steps done")
    }

    private func color(for index: Int) -> Color {
        if index < completed { return .green }
        if index == completed { return tint }
        return .white.opacity(0.22)
    }
}

/// Interactive button: completes the step via the app (LiveActivityIntent).
/// Before the wait is over it's muted; the app's constraint check would
/// refuse an early press anyway.
private struct MarkDoneButton: View {
    let attributes: StepTimerAttributes
    let ready: Bool
    let tint: Color

    var body: some View {
        Button(intent: CompleteTimedStepIntent(recordId: attributes.recordId, stepId: attributes.stepId)) {
            Label("Mark done", systemImage: "checkmark")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(ready ? Color.green : .white.opacity(0.08), in: Capsule())
                .foregroundStyle(ready ? .black : .white.opacity(0.45))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Lock Screen

private struct LockScreenTimerView: View {
    let context: ActivityViewContext<StepTimerAttributes>

    var body: some View {
        let look = TimerLook(context: context)
        VStack(alignment: .leading, spacing: 14) {
            // Brand row
            HStack(spacing: 6) {
                Image(systemName: "flask.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(LinearGradient(colors: [Color(red: 0.32, green: 0.35, blue: 0.92), Color(red: 0.05, green: 0.66, blue: 0.62)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text("LabLog")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                Text("· \(context.attributes.labName.isEmpty ? context.attributes.labCode : context.attributes.labName)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                Spacer()
                StepDots(total: context.attributes.totalSteps, completed: context.state.completedSteps,
                         tint: look.discipline.tint)
            }

            // Step + countdown
            HStack(alignment: .center, spacing: 12) {
                DisciplineTile(discipline: look.discipline, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("STEP \(context.attributes.stepOrder) OF \(context.attributes.totalSteps)")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(look.discipline.tint)
                    Text(context.attributes.stepTitle)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(context.attributes.experimentTitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    CountdownText(state: context.state, ready: look.ready)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(look.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(look.ready ? "READY" : "LEFT")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.5))
                        .fixedSize()
                }
                .frame(minWidth: 70, alignment: .trailing)
            }

            TimeBar(state: context.state, accent: look.accent, ready: look.ready)

            // Up next + action
            HStack(spacing: 8) {
                if let next = context.attributes.nextStepTitle {
                    Label {
                        Text("Up next: \(next)").lineLimit(1)
                    } icon: {
                        Image(systemName: "arrow.turn.down.right")
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 8)
                MarkDoneButton(attributes: context.attributes, ready: look.ready, tint: look.discipline.tint)
            }
        }
        .padding(16)
    }
}

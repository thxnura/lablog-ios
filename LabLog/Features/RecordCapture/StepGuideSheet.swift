import SwiftUI

/// Identifies which step's guide is open (UUID itself isn't Identifiable).
struct GuideTarget: Identifiable, Equatable {
    let id: UUID
}

/// The step guide: what to do, what's blocking it, and the one action that
/// moves it forward. Opened by tapping a step card, a Live Activity, or a
/// "step ready" notification. Every action still goes through the constraint
/// engine (via the model) — the guide only presents it.
struct StepGuideSheet: View {
    @Bindable var model: RecordCaptureModel
    @State private var stepId: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cameraStep: Step?
    @State private var showClockTime = false
    @State private var completedCount = 0

    private let engine = StepConstraintEngine()

    init(model: RecordCaptureModel, stepId: UUID) {
        self.model = model
        _stepId = State(initialValue: stepId)
    }

    private var step: Step? { model.steps.first { $0.id == stepId } }

    // MARK: State

    enum GuideState: Equatable {
        case completed(at: Date)
        case available
        case needsPhoto
        case waiting(remaining: Int, total: Int, readyAt: Date)
        case locked(blockers: [Step])
    }

    private func state(of step: Step, now: Date) -> GuideState {
        if let done = model.completions.first(where: { $0.stepId == step.id }) {
            return .completed(at: done.completedAt)
        }
        let times = Dictionary(model.completions.map { ($0.stepId, $0.completedAt) }, uniquingKeysWith: { a, _ in a })
        let context = StepConstraintEngine.Context(completedStepIds: Set(times.keys),
                                                   attachedPhotoStepIds: model.photoStepIds,
                                                   completionTimes: times, now: now)
        switch engine.lockReason(for: step, context: context) {
        case nil:
            return .available
        case .needsPhoto?:
            return .needsPhoto
        case .timerPending(let remaining)?:
            return .waiting(remaining: remaining, total: step.minDurationSeconds ?? remaining,
                            readyAt: now.addingTimeInterval(TimeInterval(remaining)))
        case .prerequisitesIncomplete(let ids)?:
            return .locked(blockers: model.steps.filter { ids.contains($0.id) }.sorted { $0.order < $1.order })
        }
    }

    /// The next step the student can work on after this one.
    private var nextStep: Step? {
        let context = StepConstraintEngine.Context(completedStepIds: Set(model.completions.map(\.stepId)),
                                                   attachedPhotoStepIds: model.photoStepIds,
                                                   completionTimes: [:], now: Date())
        return engine.reachableSteps(model.steps, context: context).first { $0.id != stepId }
    }

    // MARK: Body

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            if let step {
                let state = state(of: step, now: timeline.date)
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.xl) {
                        header(step, state: state)
                        statusPanel(step, state: state)
                            .transition(.blurReplace)
                        if let guide = step.guide {
                            guideSections(guide)
                        }
                    }
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.top, Theme.Space.xl)
                    .padding(.bottom, Theme.Space.l)
                    .id(step.id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
                }
                .background(Theme.canvas)
                .safeAreaInset(edge: .bottom) {
                    primaryAction(step, state: state)
                        .padding(.horizontal, Theme.Space.l)
                        .padding(.vertical, Theme.Space.m)
                        .background(.bar)
                }
                .overlay(alignment: .topTrailing) { closeButton }
                .animation(Theme.spring, value: state)
                .animation(Theme.spring, value: stepId)
            }
        }
        .sheet(item: $cameraStep) { step in
            CameraPicker(onCaptured: { image in
                cameraStep = nil
                attachPhoto(image, to: step)
            }, onCancel: { cameraStep = nil })
            .ignoresSafeArea()
        }
        .sensoryFeedback(.success, trigger: completedCount)
        .presentationDetents([.fraction(0.82), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.canvas)
        // No container-level accessibilityIdentifier here: SwiftUI pushes it down
        // onto every child, replacing their own ids (failure 005).
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Theme.inset, in: Circle())
        }
        .padding(Theme.Space.l)
        .accessibilityLabel("Close guide")
        .accessibilityIdentifier("close-guide")
    }

    // MARK: Header

    private func header(_ step: Step, state: GuideState) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Step \(step.order) of \(model.steps.count)").eyebrow()
            Text(step.title)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 40)
            if let instruction = step.instruction {
                Text(instruction)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                if step.requiresPhoto {
                    MetaChip(symbol: "camera.fill", text: "Photo evidence", tint: Theme.caution)
                }
                if let seconds = step.minDurationSeconds {
                    MetaChip(symbol: "timer", text: "Wait \(Self.format(seconds))", tint: Theme.caution)
                }
                if !step.prerequisiteStepIds.isEmpty {
                    let orders = model.steps.filter { step.prerequisiteStepIds.contains($0.id) }.map(\.order).sorted()
                    MetaChip(symbol: "arrow.turn.down.right",
                             text: "After " + orders.map { "Step \($0)" }.joined(separator: " & "))
                }
            }
        }
    }

    // MARK: Status

    @ViewBuilder
    private func statusPanel(_ step: Step, state: GuideState) -> some View {
        switch state {
        case .waiting(let remaining, let total, let readyAt):
            VStack(spacing: Theme.Space.l) {
                TimerDial(remaining: remaining, total: total, readyAt: readyAt, showClockTime: $showClockTime)
                VStack(spacing: 6) {
                    Label("Also counting down in the Dynamic Island", systemImage: "iphone.gen3")
                    Label("We'll notify you at \(readyAt.formatted(date: .omitted, time: .shortened))", systemImage: "bell.badge")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .card(padding: Theme.Space.xl)

        case .locked(let blockers):
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Label("Finish these first", systemImage: "lock.fill")
                    .font(.headline)
                ForEach(blockers) { blocker in
                    Button {
                        withAnimation(Theme.spring) { stepId = blocker.id }
                    } label: {
                        HStack(spacing: Theme.Space.m) {
                            Image(systemName: "circle")
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Step \(blocker.order)").eyebrow()
                                Text(blocker.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                            }
                            Spacer()
                            Text("Open")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(Theme.Space.m)
                        .background(Theme.inset, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    }
                    .buttonStyle(.pressableCard)
                }
            }
            .card()

        case .needsPhoto:
            statusRow(symbol: "camera.fill", tint: Theme.caution,
                      title: "Photo evidence needed",
                      detail: "Take the photo and this step is marked done automatically.")

        case .available:
            statusRow(symbol: "hand.tap.fill", tint: .accentColor,
                      title: "Ready when you are",
                      detail: model.isEditable ? "Work through the guide below, then mark the step done." : "This record has been submitted.")

        case .completed(let at):
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.success)
                    .symbolEffect(.bounce, value: completedCount)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Done").font(.headline)
                    Text("Completed at \(at.formatted(date: .omitted, time: .shortened))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let attachment = model.attachments.first(where: { $0.stepId == step.id }),
                   let name = attachment.localPath,
                   let image = EvidenceStore.image(for: name)?.preparingThumbnail(of: CGSize(width: 160, height: 160)) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .card()
        }
    }

    private func statusRow(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    // MARK: Guide content

    @ViewBuilder
    private func guideSections(_ guide: StepGuide) -> some View {
        if !guide.steps.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionHeader(title: "How to do it")
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, text in
                        HStack(alignment: .top, spacing: Theme.Space.m) {
                            Text("\(index + 1)")
                                .font(.system(.footnote, design: .rounded, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 24, height: 24)
                                .background(Color.accentColor.opacity(0.14), in: Circle())
                            Text(text)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .card()
            }
        }
        if let safety = guide.safety {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.caution)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Safety").font(.subheadline.weight(.bold))
                    Text(safety)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.caution.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        if let expected = guide.expected {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Image(systemName: "eye.fill")
                    .foregroundStyle(Theme.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text("What you should see").font(.subheadline.weight(.bold))
                    Text(expected)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
        }
    }

    // MARK: Action

    @ViewBuilder
    private func primaryAction(_ step: Step, state: GuideState) -> some View {
        if !model.isEditable {
            actionButton("Close", symbol: nil, tint: .accentColor) { dismiss() }
        } else {
            switch state {
            case .available:
                actionButton("Mark step done", symbol: "checkmark", tint: Theme.success) {
                    if model.complete(step) { completedCount += 1 }
                }
                .accessibilityIdentifier("guide-mark-done")
            case .needsPhoto:
                actionButton("Take evidence photo", symbol: "camera.fill", tint: Theme.caution) {
                    requestPhoto(for: step)
                }
                .accessibilityIdentifier("guide-take-photo")
            case .waiting(let remaining, _, _):
                actionButton("Available in \(Self.format(remaining))", symbol: "hourglass", tint: Theme.caution) {}
                    .disabled(true)
            case .locked(let blockers):
                actionButton("Finish Step \(blockers.first?.order ?? 0) first", symbol: "lock.fill", tint: .secondary) {}
                    .disabled(true)
            case .completed:
                if let next = nextStep {
                    actionButton("Next: Step \(next.order) · \(next.title)", symbol: "arrow.right", tint: .accentColor) {
                        withAnimation(Theme.spring) { stepId = next.id }
                    }
                    .accessibilityIdentifier("guide-next")
                } else {
                    actionButton("Back to checklist", symbol: nil, tint: .accentColor) { dismiss() }
                }
            }
        }
    }

    private func actionButton(_ title: String, symbol: String?, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PrimaryButtonLabel(title: title, symbol: symbol)
                .lineLimit(1)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(tint)
        .contentTransition(.numericText(countsDown: true))
    }

    // MARK: Photo

    private func requestPhoto(for step: Step) {
        #if DEBUG
        if CameraStub.isEnabled {
            attachPhoto(CameraStub.image(), to: step)
            return
        }
        #endif
        cameraStep = step
    }

    private func attachPhoto(_ image: UIImage, to step: Step) {
        let wasDone = model.completions.contains { $0.stepId == step.id }
        model.attachPhoto(image, to: step)
        if !wasDone && model.completions.contains(where: { $0.stepId == step.id }) {
            completedCount += 1
        }
    }

    static func format(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Big countdown ring. Tap to switch between time remaining and the clock
/// time the step becomes available.
private struct TimerDial: View {
    let remaining: Int
    let total: Int
    let readyAt: Date
    @Binding var showClockTime: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double {
        guard total > 0 else { return 1 }
        return 1 - Double(remaining) / Double(total)
    }

    var body: some View {
        Button {
            withAnimation(.snappy) { showClockTime.toggle() }
        } label: {
            ZStack {
                Circle()
                    .stroke(Theme.caution.opacity(0.15), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(AngularGradient(colors: [Theme.caution.opacity(0.6), Theme.caution], center: .center),
                            style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    // One linear segment per tick reads as a continuous sweep.
                    .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)
                VStack(spacing: 2) {
                    Text(showClockTime ? readyAt.formatted(date: .omitted, time: .shortened) : StepGuideSheet.format(remaining))
                        .font(.system(size: showClockTime ? 34 : 46, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    Text(showClockTime ? "ready at" : "remaining")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
            .frame(width: 196, height: 196)
            .contentShape(Circle())
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel("Timer")
        .accessibilityValue("\(remaining / 60) minutes \(remaining % 60) seconds remaining, ready at \(readyAt.formatted(date: .omitted, time: .shortened))")
        .accessibilityHint("Double-tap to switch between remaining time and ready time")
        .accessibilityIdentifier("timer-dial")
    }
}

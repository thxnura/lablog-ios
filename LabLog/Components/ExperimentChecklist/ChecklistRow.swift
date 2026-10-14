import SwiftUI

/// A single step in the ExperimentChecklist timeline: a status node on the
/// left rail, a connector down to the next step, and the step card.
struct ChecklistRow: View {
    enum RowState: Equatable {
        case locked(reason: String)
        case available
        case completed(at: Date)
        case needsPhoto
        /// `progress` runs 0 → 1 as the wait elapses.
        case timerPending(text: String, progress: Double)
    }

    let step: Step
    let state: RowState
    let style: ChecklistStyle
    var isLast = false
    /// Connector below this node is "filled" once this step is done.
    var connectorFilled = false
    var thumbnail: UIImage?
    /// Tapping the status circle: complete / take photo / explain the lock.
    let onNodeTap: () -> Void
    /// Tapping the card: open the step guide (falls back to `onNodeTap`).
    var onCardTap: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Button(action: onNodeTap) {
                node
                    // A taller hit area than the 30-pt circle itself.
                    .padding(.bottom, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressableCard)
            .accessibilityLabel(nodeAccessibilityLabel)
            .accessibilityIdentifier("step-node-\(step.order)")

            Button(action: onCardTap ?? onNodeTap) {
                card
            }
            .buttonStyle(.pressableCard)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Step \(step.order), \(step.title)")
            .accessibilityValue(accessibilityState)
            .accessibilityHint(onCardTap == nil ? accessibilityHint : "Double-tap to open the step guide")
            .accessibilityIdentifier("step-\(step.order)")
        }
        .background(alignment: .topLeading) { connector }
    }

    private var nodeAccessibilityLabel: String {
        switch state {
        case .available: "Mark step \(step.order) done"
        case .needsPhoto: "Take photo for step \(step.order)"
        case .completed: "Step \(step.order) done"
        case .timerPending, .locked: "Step \(step.order) locked"
        }
    }

    // MARK: Rail

    private var connector: some View {
        Rectangle()
            .fill(connectorFilled ? style.completedTint : Color.secondary.opacity(0.22))
            .frame(width: 2)
            .padding(.top, style.nodeSize + 4)
            .padding(.leading, style.nodeSize / 2 - 1)
            .padding(.bottom, -style.rowSpacing + 2)
            .opacity(isLast ? 0 : 1)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var node: some View {
        let size = style.nodeSize
        ZStack {
            switch state {
            case .completed:
                Circle().fill(style.completedTint)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            case .available:
                Circle().strokeBorder(style.availableTint, lineWidth: 2.5)
                Circle().fill(style.availableTint).padding(size * 0.3)
            case .needsPhoto:
                Circle().fill(style.guardTint.opacity(0.16))
                Image(systemName: "camera.fill")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(style.guardTint)
            case .timerPending(_, let progress):
                Circle().stroke(style.guardTint.opacity(0.18), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(style.guardTint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "hourglass")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(style.guardTint)
            case .locked:
                Circle().fill(Color.secondary.opacity(0.14))
                Image(systemName: "lock.fill")
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(style.lockedTint)
            }
        }
        .frame(width: size, height: size)
        .padding(.top, 14)
        .animation(reduceMotion ? nil : .bouncy(duration: 0.4), value: isCompleted)
    }

    // MARK: Card

    private var card: some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Step \(step.order)")
                    .eyebrow()
                    .foregroundStyle(eyebrowTint)
                Text(step.title)
                    .font(.headline)
                    .foregroundStyle(isLocked ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let instruction = step.instruction, !(isCompleted && style.collapsesCompletedSteps) {
                    Text(instruction)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                statusLine
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            if onCardTap != nil && thumbnail == nil {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .padding(Theme.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardFill, in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
                .strokeBorder(borderTint, lineWidth: borderWidth)
        }
        .shadow(color: shadowTint, radius: 12, y: 5)
        .opacity(isLocked ? style.lockedOpacity + 0.25 : 1)
        .contentShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var statusLine: some View {
        switch state {
        case .timerPending(let text, _):
            HStack(spacing: 6) {
                Image(systemName: "timer")
                Text(text)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
            }
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(style.guardTint)
        default:
            HStack(spacing: 5) {
                Image(systemName: statusIcon)
                Text(statusText)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusTint)
        }
    }

    // MARK: State → appearance

    private var isLocked: Bool {
        if case .locked = state { return true }
        return false
    }

    private var isCompleted: Bool {
        if case .completed = state { return true }
        return false
    }

    private var isActionable: Bool {
        switch state {
        case .available, .needsPhoto: true
        default: false
        }
    }

    private var cardFill: AnyShapeStyle {
        isCompleted ? AnyShapeStyle(style.completedTint.opacity(0.09)) : AnyShapeStyle(Theme.surface)
    }

    private var borderTint: Color {
        switch state {
        case .available: style.availableTint
        case .needsPhoto, .timerPending: style.guardTint.opacity(0.7)
        default: .clear
        }
    }

    private var borderWidth: CGFloat {
        switch state {
        case .available, .needsPhoto, .timerPending: 1.5
        default: 0
        }
    }

    /// Only the steps that want attention are lifted off the page.
    private var shadowTint: Color {
        switch state {
        case .available: style.availableTint.opacity(0.18)
        case .needsPhoto, .timerPending: style.guardTint.opacity(0.16)
        default: .clear
        }
    }

    private var eyebrowTint: Color {
        switch state {
        case .completed: style.completedTint
        case .available: style.availableTint
        case .needsPhoto, .timerPending: style.guardTint
        case .locked: .secondary
        }
    }

    private var statusText: String {
        switch state {
        case .locked(let reason): reason
        case .needsPhoto: "Tap the circle to take the evidence photo"
        case .timerPending(let text, _): text
        case .completed(let at): "Done at \(at.formatted(date: .omitted, time: .shortened))"
        case .available: step.requiresPhoto ? "Photo attached · tap the circle to finish" : "Tap the circle to mark done"
        }
    }

    private var statusIcon: String {
        switch state {
        case .locked: "lock"
        case .needsPhoto: "camera"
        case .timerPending: "timer"
        case .completed: "checkmark.circle.fill"
        case .available: "hand.tap.fill"
        }
    }

    private var statusTint: Color {
        switch state {
        case .completed: style.completedTint
        case .needsPhoto, .timerPending: style.guardTint
        case .available: style.availableTint
        case .locked: style.lockedTint
        }
    }

    private var accessibilityState: String {
        switch state {
        case .locked(let reason): "Locked. \(reason)"
        case .available: "Available"
        case .completed(let at): "Completed at \(at.formatted(date: .omitted, time: .shortened))"
        case .needsPhoto: "Needs a photo"
        case .timerPending(let text, _): text
        }
    }

    private var accessibilityHint: String {
        switch state {
        case .available: "Double-tap to mark done"
        case .needsPhoto: "Double-tap to open the camera"
        case .locked: "Double-tap to hear why it's locked"
        default: ""
        }
    }
}

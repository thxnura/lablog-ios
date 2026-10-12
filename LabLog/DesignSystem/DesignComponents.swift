import SwiftUI

/// Circular progress, used for experiment and record completion.
struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 6
    var tint: Color = .accentColor

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(Theme.spring, value: progress)
        .accessibilityHidden(true)
    }
}

/// Gradient tile with the discipline's symbol (chemistry flask, physics atom…).
struct DisciplineIcon: View {
    let discipline: Discipline
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: discipline.symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(discipline.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A number with a label — the dashboard stats on the Labs screen.
struct StatTile: View {
    let value: Int
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: Circle())
            Text(value, format: .number)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .card(padding: Theme.Space.m)
        .animation(Theme.spring, value: value)
        .accessibilityElement(children: .combine)
    }
}

/// Compact fact about an experiment: "5 steps", "1 photo", "5 min timer".
struct MetaChip: View {
    let symbol: String
    let text: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.inset, in: Capsule())
    }
}

/// Title-style header for a group of cards.
struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.semibold))
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, Theme.Space.s)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Label + value row inside a card (Sync screen, submission receipt).
struct InfoRow<Value: View>: View {
    let symbol: String
    let title: String
    var tint: Color = .accentColor
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title)
                .font(.subheadline)
            Spacer(minLength: Theme.Space.s)
            value
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Press feedback on touch-down with a quick, critically damped return.
/// Disabled under Reduce Motion (the highlight still comes from opacity).
struct PressableCardStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableCardStyle {
    static var pressableCard: PressableCardStyle { PressableCardStyle() }
}

/// Full-width primary call to action.
struct PrimaryButtonLabel: View {
    let title: String
    var symbol: String?
    var isLoading = false

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            if isLoading {
                ProgressView().tint(.white)
            } else if let symbol {
                Image(systemName: symbol)
            }
            Text(title)
        }
        .font(.headline)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

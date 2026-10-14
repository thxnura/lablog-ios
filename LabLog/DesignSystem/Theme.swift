import SwiftUI

/// LabLog design tokens. Every colour, radius and spacing value used by the
/// screens comes from here, so the visual language stays consistent and can be
/// defended as a set of deliberate choices.
enum Theme {
    // MARK: Colour — semantic first; brand accent lives in Assets (AccentColor).
    static let success = Color(red: 0.16, green: 0.68, blue: 0.42)
    /// Photo / timer guards: reachable, but one condition left.
    static let caution = Color(red: 0.96, green: 0.56, blue: 0.08)
    static let danger = Color(red: 0.91, green: 0.26, blue: 0.24)
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let inset = Color(uiColor: .tertiarySystemFill)

    // MARK: Shape
    enum Radius {
        static let card: CGFloat = 22
        static let tile: CGFloat = 16
        static let control: CGFloat = 14
    }

    // MARK: Spacing (4-pt grid)
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // MARK: Motion — critically damped by default (no overshoot); bounce is
    // reserved for moments that carry momentum, like completing a step.
    static let spring = Animation.smooth(duration: 0.35)
    static let snappy = Animation.snappy(duration: 0.25)
}

// MARK: - Surfaces

private struct CardModifier: ViewModifier {
    var padding: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            // A soft lift in light mode only; dark mode separates by tone instead.
            .shadow(color: .black.opacity(scheme == .light ? 0.05 : 0), radius: 14, y: 6)
    }
}

extension View {
    /// The standard LabLog surface: rounded, padded, lifted off the canvas.
    func card(padding: CGFloat = Theme.Space.l) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Small uppercase label above a title ("STEP 2", "CONTINUE").
    func eyebrow() -> some View {
        font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    /// A bottom bar that floats over scrolling content. Uses the iOS 26 scroll
    /// edge effect where available, and a material background before that.
    @ViewBuilder
    func bottomActionBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        if #available(iOS 26.0, *) {
            safeAreaBar(edge: .bottom) {
                bar()
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.vertical, Theme.Space.s)
            }
        } else {
            safeAreaInset(edge: .bottom) {
                bar()
                    .padding(.horizontal, Theme.Space.l)
                    .padding(.vertical, Theme.Space.m)
                    .background(.bar)
            }
        }
    }
}

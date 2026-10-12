import SwiftUI

/// Theming for the ExperimentChecklist custom component.
struct ChecklistStyle {
    var rowSpacing: CGFloat = 14
    var cornerRadius: CGFloat = 18
    var nodeSize: CGFloat = 30
    var lockedOpacity: Double = 0.5
    var completedTint: Color = Theme.success
    var availableTint: Color = .accentColor
    /// Photo / timer guards — the step is reachable but has a condition left.
    var guardTint: Color = Theme.caution
    var lockedTint: Color = .secondary
    /// Collapse finished steps to title + time so the eye lands on what's next.
    var collapsesCompletedSteps: Bool = true

    static let `default` = ChecklistStyle()
}

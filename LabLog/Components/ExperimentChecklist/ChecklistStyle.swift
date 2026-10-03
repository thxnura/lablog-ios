import SwiftUI

/// Theming for the ExperimentChecklist custom component.
struct ChecklistStyle {
    var rowSpacing: CGFloat = 12
    var cornerRadius: CGFloat = 12
    var lockedOpacity: Double = 0.5
    var completedTint: Color = .green
    var availableTint: Color = .accentColor
    var lockedTint: Color = .secondary

    static let `default` = ChecklistStyle()
}

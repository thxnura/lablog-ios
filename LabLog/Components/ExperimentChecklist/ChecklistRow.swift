import SwiftUI

/// A single row in the ExperimentChecklist. Renders one of five visual states.
struct ChecklistRow: View {
    enum RowState: Equatable {
        case locked(reason: String)
        case available
        case completed(at: Date)
        case needsPhoto
        case timerPending(text: String)
    }

    let step: Step
    let state: RowState
    let style: ChecklistStyle
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 4) {
                    Text("Step \(step.order): \(step.title)")
                        .font(.headline)
                    if let instruction = step.instruction {
                        Text(instruction)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(subtitleTint)
                    }
                }
                Spacer()
            }
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: style.cornerRadius))
            .opacity(isLocked ? style.lockedOpacity : 1)
        }
        .buttonStyle(.plain)
        .disabled(false) // locked rows still tappable so we can show the reason
    }

    private var isLocked: Bool {
        if case .available = state { return false }
        if case .completed = state { return false }
        return true
    }

    private var icon: some View {
        Image(systemName: iconName)
            .font(.title2)
            .foregroundStyle(iconTint)
    }

    private var iconName: String {
        switch state {
        case .completed: return "checkmark.circle.fill"
        case .available: return "circle"
        case .needsPhoto: return "camera.circle"
        case .timerPending: return "clock"
        case .locked: return "lock.fill"
        }
    }

    private var iconTint: Color {
        switch state {
        case .completed: return style.completedTint
        case .available: return style.availableTint
        default: return style.lockedTint
        }
    }

    private var subtitle: String? {
        switch state {
        case .locked(let reason): return reason
        case .needsPhoto: return "Attach a photo to complete this step"
        case .timerPending(let text): return text
        case .completed(let at): return "Done · \(at.formatted(date: .omitted, time: .shortened))"
        case .available: return step.requiresPhoto ? "Photo required" : nil
        }
    }

    private var subtitleTint: Color {
        switch state {
        case .completed: return style.completedTint
        default: return style.lockedTint
        }
    }
}

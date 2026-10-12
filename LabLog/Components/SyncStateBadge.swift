import SwiftUI

/// Small capsule showing where a record is in the sync lifecycle.
struct SyncStateBadge: View {
    let state: SyncState

    var body: some View {
        // Explicit HStack rather than Label: in a List row the automatic label
        // style can collapse to icon-only once space is tight.
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(title)
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(tint)
        .background(tint.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sync: \(title)")
    }

    private var title: String {
        switch state {
        case .pendingCreate, .pendingUpdate: "Pending"
        case .synced: "Synced"
        case .failed: "Failed"
        }
    }

    private var icon: String {
        switch state {
        case .pendingCreate, .pendingUpdate: "arrow.triangle.2.circlepath"
        case .synced: "checkmark.icloud.fill"
        case .failed: "exclamationmark.icloud.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .pendingCreate, .pendingUpdate: Theme.caution
        case .synced: Theme.success
        case .failed: Theme.danger
        }
    }
}

/// Status chip for a record's lifecycle (draft vs submitted).
struct RecordStatusBadge: View {
    let status: RecordStatus

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: status == .submitted ? "checkmark.seal.fill" : "pencil")
            Text(status == .submitted ? "Submitted" : "Draft")
        }
        .font(.caption2.weight(.semibold))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(status == .submitted ? Color.accentColor : .secondary)
        .background((status == .submitted ? Color.accentColor : Color.secondary).opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// Toolbar pill: connectivity + outbox size, visible on every main screen.
struct ConnectivityPill: View {
    let isOnline: Bool
    let pendingCount: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isOnline ? Theme.success : Theme.caution)
                .frame(width: 7, height: 7)
            Text(isOnline ? "Online" : "Offline")
            if pendingCount > 0 {
                Text("\(pendingCount)")
                    .monospacedDigit()
                    .padding(.horizontal, 5)
                    .background(Theme.caution.opacity(0.18), in: Capsule())
                    .foregroundStyle(Theme.caution)
                    .contentTransition(.numericText(value: Double(pendingCount)))
            }
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 4)
        .animation(Theme.spring, value: pendingCount)
        .animation(Theme.spring, value: isOnline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOnline ? "Online" : "Offline")
        .accessibilityValue(pendingCount > 0 ? "\(pendingCount) waiting to sync" : "")
        .accessibilityIdentifier("connectivity-pill")
    }
}

import SwiftUI

/// What the toolbar's sync indicator shows. Pure, so the rules are testable:
/// quiet when everything is fine, specific when it isn't.
enum SyncIndicatorState: Equatable {
    /// The build has no server: everything stays on the phone.
    case onDevice
    case offline
    case syncing
    case failed(String)
    case signedOut
    case waiting
    case synced

    init(isConfigured: Bool, isOnline: Bool, status: SyncEngine.Status, pendingCount: Int) {
        if !isConfigured { self = .onDevice; return }
        if !isOnline { self = .offline; return }
        switch status {
        case .syncing: self = .syncing
        case .failed(let message): self = .failed(message)
        case .signedOut where pendingCount > 0: self = .signedOut
        default: self = pendingCount > 0 ? .waiting : .synced
        }
    }

    var symbol: String {
        switch self {
        case .onDevice: "internaldrive"
        case .offline: "icloud.slash"
        case .syncing: "arrow.triangle.2.circlepath"
        case .failed: "exclamationmark.icloud"
        case .signedOut: "icloud.and.arrow.up"
        case .waiting: "icloud.and.arrow.up"
        case .synced: "checkmark.icloud"
        }
    }

    var tint: Color {
        switch self {
        case .onDevice, .synced: .secondary
        case .offline, .signedOut: Theme.caution
        case .syncing, .waiting: .accentColor
        case .failed: Theme.danger
        }
    }

    /// A word next to the icon, only for the state that changes what you can do.
    var shortText: String? { self == .offline ? "Offline" : nil }

    /// Show the outbox size next to the icon (not when all is synced).
    var showsCount: Bool {
        switch self {
        case .offline, .waiting, .syncing, .signedOut, .failed: true
        case .onDevice, .synced: false
        }
    }

    var canSyncNow: Bool {
        switch self {
        case .waiting, .failed: true
        default: false
        }
    }

    func title(pending n: Int) -> String {
        let records = "\(n) record\(n == 1 ? "" : "s")"
        switch self {
        case .onDevice: return "Saved on this iPhone"
        case .offline: return "You're offline"
        case .syncing: return "Syncing \(records)…"
        case .failed: return "Sync didn't finish"
        case .signedOut: return "Sign in to sync"
        case .waiting: return "\(records) waiting to upload"
        case .synced: return "Everything is synced"
        }
    }

    func detail(pending n: Int) -> String {
        let records = "\(n) record\(n == 1 ? " is" : "s are")"
        switch self {
        case .onDevice: return "This build has no server, so records stay on this iPhone."
        case .offline: return n == 0
            ? "Keep working: everything is saved on this iPhone and syncs when you're back online."
            : "\(records) saved on this iPhone and will upload when you're back online."
        case .syncing: return "Uploading photos first, then records."
        case .failed(let message): return message
        case .signedOut: return "\(records) saved on this iPhone. Sign in from the Sync tab to upload."
        case .waiting: return "They upload automatically in a moment."
        case .synced: return "Your records and photos are on the server."
        }
    }

    func accessibilityValue(pending n: Int) -> String {
        title(pending: n) + (showsCount && n > 0 && self != .waiting && self != .syncing ? ", \(n) waiting" : "")
    }
}

/// The toolbar's sync status: an icon (plus "Offline", or the outbox size,
/// when they matter). Tap for a one-sentence explanation and "Sync now".
struct SyncStatusButton: View {
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showDetails = false

    private var pending: Int { app.sync.pendingCount }

    private var state: SyncIndicatorState {
        SyncIndicatorState(isConfigured: app.config.isBackendConfigured, isOnline: app.reachability.isOnline,
                           status: app.sync.status, pendingCount: pending)
    }

    var body: some View {
        let state = self.state
        Button { showDetails = true } label: {
            HStack(spacing: 5) {
                Image(systemName: state.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(state.tint)
                    .symbolEffect(.pulse, options: .repeating, isActive: state == .syncing && !reduceMotion)
                    .contentTransition(.symbolEffect(.replace))
                if let text = state.shortText {
                    Text(text)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(state.tint)
                }
                if state.showsCount && pending > 0 {
                    Text("\(pending)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(pending)))
                }
            }
            .animation(Theme.spring, value: state)
            .animation(Theme.spring, value: pending)
        }
        .popover(isPresented: $showDetails, arrowEdge: .top) {
            SyncStatusPopover(state: state, pending: pending, lastSyncedAt: app.sync.lastSyncedAt) {
                Task { await app.sync.sync() }
            }
            .presentationCompactAdaptation(.popover)
        }
        .accessibilityLabel("Sync status")
        .accessibilityValue(state.accessibilityValue(pending: pending))
        .accessibilityHint("Shows details and Sync now")
        .accessibilityIdentifier("sync-indicator")
    }
}

/// The explanation behind the toolbar icon, in one sentence, with the one
/// action that helps (if any).
private struct SyncStatusPopover: View {
    let state: SyncIndicatorState
    let pending: Int
    let lastSyncedAt: Date?
    let onSyncNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Image(systemName: state.symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.title2)
                    .foregroundStyle(state.tint)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(state.title(pending: pending))
                        .font(.headline)
                    Text(state.detail(pending: pending))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let lastSyncedAt {
                        Text("Last synced \(lastSyncedAt.formatted(.relative(presentation: .named)))")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                }
            }
            if state.canSyncNow {
                Button(action: onSyncNow) {
                    Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("sync-now-popover")
            }
        }
        .padding(Theme.Space.l)
        .frame(width: 300)
        .accessibilityIdentifier("sync-status-details")
    }
}

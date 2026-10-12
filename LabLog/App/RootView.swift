import SwiftUI

/// Three tabs, shallow stacks: a student mid-experiment is never more than
/// three taps from the checklist, and sync never blocks the lab work.
struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        TabView {
            NavigationStack {
                LabListView()
            }
            .tabItem { Label("Labs", systemImage: "flask.fill") }

            NavigationStack {
                RecordsListView()
            }
            .tabItem { Label("Records", systemImage: "list.bullet.clipboard.fill") }

            NavigationStack {
                SyncStatusView()
            }
            .tabItem { Label("Sync", systemImage: "arrow.clockwise.icloud.fill") }
            .badge(app.sync.pendingCount)
        }
    }
}

/// Shared toolbar item: connectivity + outbox size.
struct ConnectivityToolbarItem: ToolbarContent {
    @Environment(AppModel.self) private var app

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            ConnectivityPill(isOnline: app.reachability.isOnline, pendingCount: app.sync.pendingCount)
        }
    }
}

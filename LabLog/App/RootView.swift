import SwiftUI

/// Three tabs, shallow stacks: a student mid-experiment is never more than
/// three taps from the checklist, and sync never blocks the lab work.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var tab: Tab = .labs
    @State private var labsPath = NavigationPath()

    enum Tab: Hashable { case labs, records, sync }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack(path: $labsPath) {
                LabListView()
            }
            .tabItem { Label("Labs", systemImage: "flask.fill") }
            .tag(Tab.labs)

            NavigationStack {
                RecordsListView()
            }
            .tabItem { Label("Records", systemImage: "list.bullet.clipboard.fill") }
            .tag(Tab.records)

            NavigationStack {
                SyncStatusView()
            }
            .tabItem { Label("Sync", systemImage: "arrow.clockwise.icloud.fill") }
            .badge(app.sync.pendingCount)
            .tag(Tab.sync)
        }
        // Dynamic Island / Lock Screen / notification → record → step guide.
        .onOpenURL { app.open($0) }
        .onChange(of: app.pendingDeepLink) { _, link in
            guard let link, app.visibleRecordId != link.recordId else { return }
            tab = .labs
            var path = NavigationPath()
            path.append(RecordRoute(id: link.recordId))
            labsPath = path
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

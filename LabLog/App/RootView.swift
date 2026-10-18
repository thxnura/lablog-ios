import SwiftUI

/// Sign-in first (ADR-027), then three tabs with shallow stacks: a student
/// mid-experiment is never more than three taps from the checklist, and sync
/// never blocks the lab work.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var tab: Tab = .labs
    @State private var labsPath = NavigationPath()

    enum Tab: Hashable { case labs, records, review, manage, sync }

    var body: some View {
        Group {
            if app.requiresSignIn {
                SignInView(isWelcome: true)
                    .transition(.opacity)
            } else {
                tabs
                    .transition(.opacity)
            }
        }
        .animation(Theme.spring, value: app.requiresSignIn)
        // Back from sign-out: start the next person on their first tab, not where the last one left off.
        .onChange(of: app.requiresSignIn) { _, gated in
            if gated { labsPath = NavigationPath() }
        }
        // Keyed on the account, not just the role: two students in a row are the same
        // role, and the second one used to land on the first one's last tab (034).
        .task(id: app.auth.session?.email) { tab = app.auth.role == .lecturer ? .review : .labs }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            if app.auth.role == .lecturer {
                // Lecturers don't do practicals: they review them and manage the labs
                // (ADR-029). The API enforces the role as well.
                NavigationStack {
                    ReviewView()
                }
                .tabItem { Label("Review", systemImage: "checkmark.rectangle.stack.fill") }
                .tag(Tab.review)

                NavigationStack {
                    ManageLabsView()
                }
                .tabItem { Label("Labs", systemImage: "square.stack.3d.up.fill") }
                .tag(Tab.manage)
            } else {
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
            }

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

/// Shared toolbar item: the sync status icon (see SyncStatusButton).
struct ConnectivityToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            SyncStatusButton()
        }
    }
}

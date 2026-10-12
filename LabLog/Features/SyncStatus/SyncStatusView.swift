import SwiftUI

/// Connectivity, account, and outbox state, with manual controls. This is the
/// viva demo screen: airplane mode → create record → reconnect → watch it drain.
struct SyncStatusView: View {
    @Environment(AppModel.self) private var app
    @State private var failed: [(record: LabRecord, title: String)] = []
    @State private var showSignIn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                SyncHero(status: app.sync.status,
                         pendingCount: app.sync.pendingCount,
                         lastSyncedAt: app.sync.lastSyncedAt,
                         onSync: { Task { await app.sync.sync() } })

                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionHeader(title: "Connection")
                    VStack(spacing: Theme.Space.m) {
                        InfoRow(symbol: app.reachability.isOnline ? "wifi" : "wifi.slash", title: "Network",
                                tint: app.reachability.isOnline ? Theme.success : Theme.caution) {
                            Text(app.reachability.isOnline ? "Online" : "Offline")
                        }
                        Divider()
                        InfoRow(symbol: "server.rack", title: "Server",
                                tint: app.config.isBackendConfigured ? .accentColor : .secondary) {
                            Text(app.config.apiBaseURL?.host() ?? "Not configured")
                        }
                        Divider()
                        InfoRow(symbol: "books.vertical.fill", title: "Catalog", tint: .accentColor) {
                            Text(app.sync.catalogRefreshedAt.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Bundled copy")
                        }
                    }
                    .card()
                }

                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionHeader(title: "Account")
                    VStack(spacing: Theme.Space.m) {
                        if let session = app.auth.session {
                            InfoRow(symbol: "person.crop.circle.fill", title: "Signed in", tint: Theme.success) {
                                Text(session.email ?? "Student")
                            }
                            Divider()
                            Button("Sign out", role: .destructive) { app.auth.signOut() }
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            InfoRow(symbol: "person.crop.circle.badge.questionmark", title: "Not signed in", tint: .secondary) {
                                EmptyView()
                            }
                            Button {
                                showSignIn = true
                            } label: {
                                PrimaryButtonLabel(title: "Sign in to sync", symbol: "person.fill")
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .disabled(!app.config.isBackendConfigured)
                            if !app.config.isBackendConfigured {
                                Text("This build has no server configured, so everything stays on the device. Add Config/Secrets.xcconfig to enable sync.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .card()
                }

                if !failed.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        SectionHeader(title: "Needs attention", trailing: "\(failed.count)")
                        VStack(alignment: .leading, spacing: Theme.Space.m) {
                            ForEach(failed, id: \.record.id) { item in
                                InfoRow(symbol: "exclamationmark.icloud.fill", title: item.title, tint: Theme.danger) {
                                    EmptyView()
                                }
                                Text(item.record.lastSyncError ?? "Sync failed")
                                    .font(.caption)
                                    .foregroundStyle(Theme.danger)
                                    .padding(.leading, 42)
                            }
                        }
                        .card()
                    }
                }

                if let error = app.sync.catalogError {
                    Label("Catalog refresh failed: \(error)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }

                Label("Records and photos are saved on this device first and upload automatically when you're back online. Retries back off from 2 to 32 seconds.",
                      systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.xl)
        }
        .background(Theme.canvas)
        .navigationTitle("Sync")
        .refreshable { await app.refreshAndSync() }
        .sheet(isPresented: $showSignIn) {
            SignInView()
        }
        .task(id: app.store.version) {
            failed = app.store.pendingRecords()
                .filter { $0.syncState == .failed }
                .map { ($0, app.store.experiment(id: $0.experimentId)?.title ?? "Record") }
        }
    }
}

/// Big, glanceable outbox status with the primary action.
private struct SyncHero: View {
    let status: SyncEngine.Status
    let pendingCount: Int
    let lastSyncedAt: Date?
    let onSync: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 76, height: 76)
                .background(tint.opacity(0.14), in: Circle())
                .symbolEffect(.pulse, options: .repeating, isActive: status == .syncing && !reduceMotion)
                .contentTransition(.symbolEffect(.replace))
            VStack(spacing: 4) {
                Text(title)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            // No server in this build → the action could never succeed, so hide it.
            if status != .notConfigured {
                Button(action: onSync) {
                    PrimaryButtonLabel(title: status == .syncing ? "Syncing…" : "Sync now",
                                       symbol: "arrow.triangle.2.circlepath",
                                       isLoading: status == .syncing)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .disabled(status == .syncing)
                .accessibilityIdentifier("sync-now")
            }
        }
        .frame(maxWidth: .infinity)
        .card(padding: Theme.Space.xl)
        .padding(.top, Theme.Space.s)
        .animation(Theme.spring, value: status)
    }

    private var symbol: String {
        switch status {
        case .syncing: "arrow.triangle.2.circlepath"
        case .offline: "icloud.slash.fill"
        case .notConfigured: "internaldrive.fill"
        case .signedOut: "person.crop.circle.badge.exclamationmark"
        case .failed: "exclamationmark.icloud.fill"
        case .idle: pendingCount == 0 ? "checkmark.icloud.fill" : "icloud.and.arrow.up.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .idle: pendingCount == 0 ? Theme.success : .accentColor
        case .syncing: .accentColor
        case .offline, .signedOut: Theme.caution
        case .notConfigured: .secondary
        case .failed: Theme.danger
        }
    }

    private var title: String {
        let records = "\(pendingCount) record\(pendingCount == 1 ? "" : "s")"
        switch status {
        case .idle: return pendingCount == 0 ? "Everything is synced" : "\(records) ready to sync"
        case .syncing: return "Syncing \(records)…"
        case .offline: return "Working offline"
        case .notConfigured: return "On-device mode"
        case .signedOut: return "Sign in to sync"
        case .failed: return "Sync didn't finish"
        }
    }

    private var subtitle: String {
        switch status {
        case .idle:
            if let lastSyncedAt { return "Last synced \(lastSyncedAt.formatted(.relative(presentation: .named)))." }
            return pendingCount == 0 ? "Nothing waiting." : "They'll upload automatically."
        case .syncing: return "Uploading photos first, then records."
        case .offline: return "\(pendingCount) waiting. They'll upload when you reconnect."
        case .notConfigured: return "No server in this build — \(pendingCount) record\(pendingCount == 1 ? " is" : "s are") kept safely on this iPhone."
        case .signedOut: return "Your \(pendingCount) record\(pendingCount == 1 ? " is" : "s are") saved here until you sign in."
        case .failed(let message): return message
        }
    }
}

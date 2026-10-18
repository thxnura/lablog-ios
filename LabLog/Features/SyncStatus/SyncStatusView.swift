import SwiftUI

/// Connectivity, account, and outbox state, with manual controls. This is the
/// demo screen: airplane mode → create record → reconnect → watch it drain.
struct SyncStatusView: View {
    @Environment(AppModel.self) private var app
    @State private var failed: [(record: LabRecord, title: String)] = []
    @State private var showSignIn = false
    @State private var showServer = false
    @State private var confirmSignOut = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                SyncHero(status: app.sync.status,
                         pendingCount: app.sync.pendingCount,
                         lastSyncedAt: app.sync.lastSyncedAt,
                         onSync: { Task { await app.sync.sync() } },
                         onSignIn: { showSignIn = true })

                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    SectionHeader(title: "Connection")
                    VStack(spacing: Theme.Space.m) {
                        InfoRow(symbol: app.reachability.isOnline ? "wifi" : "wifi.slash", title: "Network",
                                tint: app.reachability.isOnline ? Theme.success : Theme.caution) {
                            Text(app.reachability.isOnline ? "Online" : "Offline")
                        }
                        Divider()
                        Button {
                            showServer = true
                        } label: {
                            InfoRow(symbol: "server.rack", title: "Server",
                                    tint: app.config.isBackendConfigured ? .accentColor : .secondary) {
                                HStack(spacing: 6) {
                                    Text(app.serverHost ?? "Not configured")
                                        .monospacedDigit()
                                    if app.config.isBackendConfigured && !app.config.isHosted {
                                        Image(systemName: "chevron.right")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // A hosted backend has a fixed address; only the local stack's can change.
                        .disabled(!app.config.isBackendConfigured || app.config.isHosted)
                        .accessibilityIdentifier("server-row")
                        .accessibilityHint(app.config.isHosted ? "" : "Change the server address")
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
                            Button("Sign out", role: .destructive) {
                                // Signing out clears this iPhone; warn if that would lose work.
                                if app.sync.pendingCount > 0 { confirmSignOut = true } else { app.signOut() }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("sign-out")
                            .alert("Sign out and delete unsent work?", isPresented: $confirmSignOut) {
                                Button("Sign Out", role: .destructive) { app.signOut() }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text(app.sync.pendingCount == 1
                                     ? "1 record hasn't uploaded yet. Signing out removes your records from this iPhone, so it will be lost."
                                     : "\(app.sync.pendingCount) records haven't uploaded yet. Signing out removes your records from this iPhone, so they will be lost.")
                            }
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
                            .accessibilityIdentifier("sign-in")
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
        .sheet(isPresented: $showServer) {
            ServerSettingsSheet()
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
    let onSignIn: () -> Void

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
            // The hero's one action is whatever unblocks sync next.
            if status == .signedOut {
                Button(action: onSignIn) {
                    PrimaryButtonLabel(title: "Sign in", symbol: "person.fill")
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .accessibilityIdentifier("hero-sign-in")
            } else if status != .notConfigured {
                // (No server in this build → syncing could never succeed, so no button.)
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
        let records = "\(pendingCount) record\(pendingCount == 1 ? " is" : "s are")"
        switch status {
        case .idle:
            if let lastSyncedAt { return "Last synced \(lastSyncedAt.formatted(.relative(presentation: .named)))." }
            return pendingCount == 0 ? "Nothing waiting." : "They'll upload automatically."
        case .syncing: return "Uploading photos first, then records."
        case .offline: return pendingCount == 0
            ? "Your work is saved on this iPhone and syncs when you reconnect."
            : "\(pendingCount) waiting. They'll upload when you reconnect."
        case .notConfigured: return pendingCount == 0
            ? "No server in this build, so records stay on this iPhone."
            : "No server in this build — \(records) kept safely on this iPhone."
        case .signedOut: return pendingCount == 0
            ? "Your lab records stay on this iPhone until you sign in."
            : "Your \(records) saved here until you sign in."
        case .failed(let message): return message
        }
    }
}

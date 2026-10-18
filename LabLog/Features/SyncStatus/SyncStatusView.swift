import SwiftUI

/// Account, sync and connection: the app's settings page, laid out like the
/// system Settings app. The account sits on top, the sync status with its one
/// action below it, then the details, and Sign Out alone at the bottom, where
/// a destructive action belongs. Also the demo screen: airplane mode → create
/// a record → reconnect → watch it drain.
struct SyncStatusView: View {
    @Environment(AppModel.self) private var app
    @State private var failed: [(record: LabRecord, title: String)] = []
    @State private var showSignIn = false
    @State private var showServer = false
    @State private var confirmSignOut = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                if let session = app.auth.session {
                    AccountHeader(email: session.email ?? "Signed in", role: app.auth.role)
                } else if !app.config.isBackendConfigured {
                    OnDeviceHeader()
                }

                SyncHero(status: app.sync.status,
                         pendingCount: app.sync.pendingCount,
                         lastSyncedAt: app.sync.lastSyncedAt,
                         onSync: { Task { await app.sync.sync() } },
                         onSignIn: { showSignIn = true })

                if !failed.isEmpty {
                    SettingsSection(title: "Needs attention", trailing: "\(failed.count)") {
                        ForEach(Array(failed.enumerated()), id: \.element.record.id) { index, item in
                            if index > 0 { RowDivider() }
                            VStack(alignment: .leading, spacing: 4) {
                                InfoRow(symbol: "exclamationmark.icloud.fill", title: item.title, tint: Theme.danger) {
                                    EmptyView()
                                }
                                Text(item.record.lastSyncError ?? "Sync failed")
                                    .font(.caption)
                                    .foregroundStyle(Theme.danger)
                                    .padding(.leading, 42)
                            }
                        }
                    }
                }

                SettingsSection(title: "Connection") {
                    InfoRow(symbol: app.reachability.isOnline ? "wifi" : "wifi.slash", title: "Network",
                            tint: app.reachability.isOnline ? Theme.success : Theme.caution) {
                        Text(app.reachability.isOnline ? "Online" : "Offline")
                    }
                    RowDivider()
                    Button {
                        showServer = true
                    } label: {
                        InfoRow(symbol: app.config.isHosted ? "cloud.fill" : "server.rack", title: "Server",
                                tint: app.config.isBackendConfigured ? .accentColor : .secondary) {
                            HStack(spacing: 6) {
                                Text(app.serverHost ?? "Not configured")
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .truncationMode(.middle)
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
                    RowDivider()
                    InfoRow(symbol: "books.vertical.fill", title: "Lab catalog", tint: .accentColor) {
                        Text(app.sync.catalogRefreshedAt.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Bundled copy")
                    }
                } footer: {
                    if let error = app.sync.catalogError {
                        Label("Catalog refresh failed: \(error)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.danger)
                    } else {
                        Text("Records and photos are saved on this iPhone first and upload when you're online.")
                    }
                }

                SettingsSection(title: "About") {
                    InfoRow(symbol: "info.circle.fill", title: "Version", tint: .secondary) {
                        Text(Self.version)
                    }
                }

                if app.auth.session != nil {
                    Button(role: .destructive) {
                        // Signing out clears this iPhone; warn if that would lose work.
                        if app.sync.pendingCount > 0 { confirmSignOut = true } else { app.signOut() }
                    } label: {
                        Text("Sign Out")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Space.l)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableCardStyle())
                    .foregroundStyle(Theme.danger)
                    .accessibilityIdentifier("sign-out")
                    .alert("Sign out and delete unsent work?", isPresented: $confirmSignOut) {
                        Button("Sign Out", role: .destructive) { app.signOut() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(app.sync.pendingCount == 1
                             ? "1 record hasn't uploaded yet. Signing out removes your records from this iPhone, so it will be lost."
                             : "\(app.sync.pendingCount) records haven't uploaded yet. Signing out removes your records from this iPhone, so they will be lost.")
                    }
                }
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

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

/// Who is signed in: initials, email and role, like the top of Settings.
private struct AccountHeader: View {
    let email: String
    let role: AuthService.Role

    private var initials: String {
        let name = email.split(separator: "@").first.map(String.init) ?? email
        let parts = name.split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" })
        return parts.prefix(2).compactMap { $0.first.map { String($0).uppercased() } }.joined()
    }

    private var roleTitle: String { role == .lecturer ? "Lecturer" : "Student" }

    var body: some View {
        HStack(spacing: Theme.Space.l) {
            // A plain monogram, like Contacts.
            Text(initials)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(Color(uiColor: .systemGray2), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(email)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(roleTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .card()
        .padding(.top, Theme.Space.s)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Signed in as \(email), \(roleTitle)")
        .accessibilityIdentifier("account-header")
    }
}

/// A build without a server: say so plainly instead of an empty account.
private struct OnDeviceHeader: View {
    var body: some View {
        InfoRow(symbol: "internaldrive.fill", title: "On-device mode", tint: .secondary) {
            Text("No server in this build")
        }
        .card()
        .padding(.top, Theme.Space.s)
    }
}

/// A titled group of rows in one card, with an optional footnote: the
/// system Settings pattern, drawn with the design system.
private struct SettingsSection<Content: View, Footer: View>: View {
    let title: String
    var trailing: String?
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            SectionHeader(title: title, trailing: trailing)
            VStack(spacing: Theme.Space.m) { content }
                .card()
            footer
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Space.s)
        }
    }
}

extension SettingsSection where Footer == EmptyView {
    init(title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, trailing: trailing, content: content, footer: { EmptyView() })
    }
}

/// A hairline between rows, inset past the row icons like the system lists.
private struct RowDivider: View {
    var body: some View { Divider().padding(.leading, 42) }
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

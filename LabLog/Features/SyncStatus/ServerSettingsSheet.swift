import SwiftUI

/// Points the app at the backend on another address without a rebuild — the
/// Mac's IP changes with every network (home Wi-Fi, campus, a phone hotspot).
/// "Test" checks both halves the app talks to: the API and Supabase Auth.
struct ServerSettingsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var check: Check = .idle
    @FocusState private var focused: Bool

    enum Check: Equatable {
        case idle
        case checking
        case reachable(milliseconds: Int)
        case failed(String)
    }

    private var defaultHost: String? { app.endpoint.defaultConfig.apiBaseURL?.host() }
    private var trimmed: String { host.trimmingCharacters(in: .whitespaces) }
    private var isValid: Bool { AppConfig.isValidHost(trimmed) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        SectionHeader(title: "Your Mac's address")
                        VStack(alignment: .leading, spacing: Theme.Space.m) {
                            TextField(defaultHost ?? "192.168.1.8", text: $host)
                                .font(.system(.title3, design: .monospaced, weight: .semibold))
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .focused($focused)
                                .padding(Theme.Space.m)
                                .background(Theme.inset, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                                .onChange(of: host) { check = .idle }
                                .accessibilityIdentifier("server-host")
                            if !trimmed.isEmpty && !isValid {
                                Label("Enter an IP address like 172.20.10.2, or a name like mac.local.", systemImage: "exclamationmark.circle")
                                    .font(.caption)
                                    .foregroundStyle(Theme.danger)
                            }
                            checkResult
                            Button {
                                Task { await runCheck() }
                            } label: {
                                PrimaryButtonLabel(title: check == .checking ? "Testing…" : "Test connection",
                                                   symbol: "bolt.horizontal.circle", isLoading: check == .checking)
                            }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.large)
                            .disabled(!isValid || check == .checking)
                            .accessibilityIdentifier("server-test")
                        }
                        .card()
                    }

                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        SectionHeader(title: "Finding it")
                        VStack(alignment: .leading, spacing: Theme.Space.m) {
                            tip(symbol: "laptopcomputer",
                                text: "On the Mac: System Settings → Wi-Fi → Details, or run `ipconfig getifaddr en0` in Terminal.")
                            tip(symbol: "personalhotspot",
                                text: "No shared Wi-Fi? Turn on this iPhone's Personal Hotspot and join it from the Mac. The Mac's address is then usually 172.20.10.x.")
                            tip(symbol: "server.rack",
                                text: "The API (port 3100) and Supabase (port 54321) both run on that Mac. You stay signed in when the address changes.")
                        }
                        .card()
                    }

                    if let defaultHost, trimmed != defaultHost {
                        Button {
                            host = defaultHost
                        } label: {
                            Label("Use the built-in address (\(defaultHost))", systemImage: "arrow.uturn.backward")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, Theme.Space.l)
                .padding(.vertical, Theme.Space.l)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas)
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        app.setServerHost(trimmed)
                        dismiss()
                    }
                    .disabled(!isValid)
                    .accessibilityIdentifier("server-save")
                }
            }
        }
        .presentationDetents([.large])
        .onAppear { host = app.serverHost ?? defaultHost ?? "" }
    }

    @ViewBuilder
    private var checkResult: some View {
        switch check {
        case .idle, .checking:
            EmptyView()
        case .reachable(let ms):
            Label("Connected: API and sign-in both answered (\(ms) ms)", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.success)
                .accessibilityIdentifier("server-ok")
        case .failed(let message):
            // LocalizedStringKey so `code` in the message renders as code.
            Label { Text(LocalizedStringKey(message)) } icon: { Image(systemName: "xmark.octagon.fill") }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("server-failed")
        }
    }

    private func tip(symbol: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: Theme.Space.m) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Pings the API's /health, then Supabase Auth's /health (needs the anon key).
    private func runCheck() async {
        focused = false
        let candidate = app.endpoint.defaultConfig.replacingHost(trimmed)
        guard let apiURL = candidate.apiBaseURL, let supabaseURL = candidate.supabaseURL else { return }
        check = .checking
        do {
            let rtt = try await APIClient.ping(apiURL)
            var req = URLRequest(url: supabaseURL.appendingPathComponent("auth/v1/health"))
            req.timeoutInterval = 4
            req.setValue(candidate.supabaseAnonKey, forHTTPHeaderField: "apikey")
            let (_, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                check = .failed("The API answered, but Supabase on port \(supabaseURL.port ?? 54321) didn't. Is `supabase start` running?")
                return
            }
            let ms = Int(rtt.components.seconds * 1000) + Int(rtt.components.attoseconds / 1_000_000_000_000_000)
            check = .reachable(milliseconds: ms)
        } catch {
            check = .failed("Can't reach \(trimmed):\(apiURL.port ?? 3100). Check the Mac is on the same network and `npm run dev` is running.")
        }
    }
}

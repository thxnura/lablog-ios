import SwiftUI

/// Supabase email/password sign-in. It is the app's first screen (ADR-027):
/// sign in once, online, and from then on LabLog works offline in the lab and
/// syncs when a connection returns. Also used as a sheet if a session ends.
///
/// Plain and professional: the real app icon, labelled fields, one primary
/// action, help where people look for it ("Forgot password?") and only the
/// version at the bottom. The welcome screen doesn't raise the keyboard on
/// launch; the sheet does, because it was asked for.
struct SignInView: View {
    /// The app's first screen rather than a sheet: no Cancel, a welcome header.
    var isWelcome = false

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isWorking = false
    @State private var error: String?
    @State private var serverUnreachable = false
    @State private var showServer = false
    @State private var showPasswordHelp = false
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    private var canSubmit: Bool { !email.isEmpty && !password.isEmpty && !isWorking }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                    header
                    VStack(alignment: .leading, spacing: Theme.Space.l) {
                        field("Email") {
                            // verbatim: as a localized key, the address would render as a mail link
                            TextField("Email", text: $email, prompt: Text(verbatim: "name@university.edu"))
                                .textContentType(.username)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focus, equals: .email)
                                .submitLabel(.next)
                                .onSubmit { focus = .password }
                                .accessibilityIdentifier("email")
                        }
                        field("Password") {
                            HStack {
                                Group {
                                    if showPassword {
                                        TextField("Enter your password", text: $password)
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                    } else {
                                        SecureField("Enter your password", text: $password)
                                    }
                                }
                                .textContentType(.password)
                                .focused($focus, equals: .password)
                                .submitLabel(.go)
                                .onSubmit { Task { await signIn() } }
                                .accessibilityIdentifier("password")

                                Button {
                                    showPassword.toggle()
                                    focus = .password
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 28, height: 28)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                            }
                        }
                        feedback
                        Button("Forgot password?") { showPasswordHelp = true }
                            .font(.footnote.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    submitButton
                }
                .padding(.horizontal, Theme.Space.xl)
                .padding(.top, isWelcome ? 56 : Theme.Space.l)
                .padding(.bottom, Theme.Space.xl)
                .frame(maxWidth: 440) // a comfortable measure on iPad and in landscape
                .frame(maxWidth: .infinity)
                .animation(Theme.spring, value: error)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas)
            .safeAreaInset(edge: .bottom) {
                if isWelcome { footer }
            }
            .toolbar {
                if !isWelcome {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .sheet(isPresented: $showServer, onDismiss: { serverUnreachable = false; error = nil }) {
                ServerSettingsSheet()
            }
            .alert("Forgot your password?", isPresented: $showPasswordHelp) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("LabLog accounts are issued by your university. Ask your lecturer or lab coordinator to reset your password.")
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.canvas)
        .task { if !isWelcome { focus = .email } }
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Image("BrandMark")
                .resizable()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                }
                .padding(.bottom, Theme.Space.s)
                .accessibilityHidden(true)
            Text(isWelcome ? "Sign in to LabLog" : "Sign in to sync")
                .font(.largeTitle.weight(.bold))
            Text(isWelcome
                 ? "Use the account your university gave you."
                 : "Your lab records stay on this iPhone until you sign in. Nothing is lost.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(isWelcome ? "welcome" : "sign-in-header")
    }

    /// Inline status: the error, and the fix when the address is the problem.
    @ViewBuilder private var feedback: some View {
        if let error {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.danger)
                    .accessibilityIdentifier("sign-in-error")
                if serverUnreachable {
                    // Fix the address without leaving sign-in (Sync → Server, in place).
                    Button {
                        showServer = true
                    } label: {
                        Label("Change server address", systemImage: "server.rack")
                            .font(.footnote.weight(.semibold))
                    }
                    .accessibilityIdentifier("sign-in-change-server")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        }
    }

    private var submitButton: some View {
        Button {
            Task { await signIn() }
        } label: {
            PrimaryButtonLabel(title: "Sign In", isLoading: isWorking)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .disabled(!canSubmit)
        .accessibilityIdentifier("sign-in-submit")
    }

    /// The version, quietly at the bottom. (The server address isn't shown: on a
    /// local build, "Change server address" appears only when sign-in can't reach it.)
    private var footer: some View {
        Text("LabLog \(Self.version)")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Space.m)
            .background(Theme.canvas)
    }

    /// A label above a single field on its own surface.
    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text(label)
                .font(.subheadline.weight(.medium))
            content()
                .padding(.horizontal, Theme.Space.l)
                .frame(minHeight: 50)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .strokeBorder(error == nil ? Color(uiColor: .separator).opacity(0.5) : Theme.danger.opacity(0.7),
                                      lineWidth: error == nil ? 0.5 : 1)
                }
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    // MARK: Action

    private func signIn() async {
        guard canSubmit else { return }
        isWorking = true
        error = nil
        serverUnreachable = false
        defer { isWorking = false }
        do {
            try await app.auth.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            if !isWelcome { dismiss() }
            await app.refreshAndSync()
        } catch {
            self.error = error.localizedDescription
            serverUnreachable = (error as? AuthService.AuthError)?.suggestsServerChange ?? false
        }
    }
}

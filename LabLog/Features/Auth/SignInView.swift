import SwiftUI

/// Supabase email/password sign-in. Optional: lab work never waits on it —
/// only syncing does.
struct SignInView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.xl) {
                    VStack(spacing: Theme.Space.m) {
                        DisciplineIcon(discipline: .of(labCode: ""), size: 72)
                        Text("Sign in to sync")
                            .font(.title2.weight(.bold))
                        Text("Your lab records stay on this iPhone until you sign in. Nothing is lost.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, Theme.Space.xl)

                    VStack(spacing: Theme.Space.m) {
                        field {
                            TextField("University email", text: $email)
                                .textContentType(.username)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focus, equals: .email)
                                .accessibilityIdentifier("email")
                                .submitLabel(.next)
                                .onSubmit { focus = .password }
                        }
                        field {
                            SecureField("Password", text: $password)
                                .textContentType(.password)
                                .focused($focus, equals: .password)
                                .accessibilityIdentifier("password")
                                .submitLabel(.go)
                                .onSubmit { Task { await signIn() } }
                        }
                        if let error {
                            Label(error, systemImage: "exclamationmark.circle.fill")
                                .font(.footnote)
                                .foregroundStyle(Theme.danger)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity)
                        }
                    }

                    Button {
                        Task { await signIn() }
                    } label: {
                        PrimaryButtonLabel(title: "Sign in", isLoading: isWorking)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .disabled(email.isEmpty || password.isEmpty || isWorking)
                    .accessibilityIdentifier("sign-in-submit")
                }
                .padding(.horizontal, Theme.Space.xl)
                .animation(Theme.spring, value: error)
            }
            .background(Theme.canvas)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.canvas)
        // Keyboard up straight away: one less tap with gloves on.
        .task { focus = .email }
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
    }

    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, Theme.Space.l)
            .frame(height: 52)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }

    private func signIn() async {
        guard !email.isEmpty, !password.isEmpty else { return }
        isWorking = true
        error = nil
        defer { isWorking = false }
        do {
            try await app.auth.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            dismiss()
            await app.refreshAndSync()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

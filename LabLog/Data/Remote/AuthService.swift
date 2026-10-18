import Foundation
import Observation

/// Student sign-in against Supabase Auth (GoTrue REST, no SDK). The resulting
/// JWT is what the Express API verifies in `requireAuth`. The session is kept
/// in the Keychain and refreshed shortly before it expires.
@MainActor
@Observable
final class AuthService {
    struct Session: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var email: String?
    }

    enum AuthError: LocalizedError {
        case notConfigured
        case server(String)
        /// The server address didn't answer: usually the Mac's IP has changed (failure 021).
        case unreachable(host: String)

        var errorDescription: String? {
            switch self {
            case .notConfigured: "Supabase isn't configured in this build (see Config/Secrets.xcconfig)."
            case .server(let message): message
            case .unreachable(let host): "Can't reach the server at \(host). If your Mac's address has changed, update it below."
            }
        }

        var isUnreachable: Bool {
            if case .unreachable = self { true } else { false }
        }
    }

    /// Errors that mean "nothing answered at that address", as opposed to no internet at all.
    private static let unreachableCodes: Set<URLError.Code> = [
        .timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost,
    ]

    private(set) var session: Session?
    var isSignedIn: Bool { session != nil }

    enum Role: String { case student, lecturer }

    /// From the JWT's `app_metadata.role`. Only used to choose what the UI
    /// shows — the API checks the role itself and returns 403 otherwise.
    var role: Role {
        guard let token = session?.accessToken,
              Self.claim("role", inAppMetadataOf: token) == "lecturer" else { return .student }
        return .lecturer
    }

    static func claim(_ key: String, inAppMetadataOf jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = payload["app_metadata"] as? [String: Any] else { return nil }
        return metadata[key] as? String
    }

    @ObservationIgnored private let endpoint: ServerEndpoint
    @ObservationIgnored private let keychain = KeychainStore(service: "com.thxnura.LabLog", account: "supabase-session")
    @ObservationIgnored private var refreshTask: Task<Session?, Never>?

    /// The session is kept across server changes: it's the same Supabase
    /// project, just reached at another address.
    init(endpoint: ServerEndpoint) {
        self.endpoint = endpoint
        if let data = keychain.load() {
            session = try? JSONDecoder().decode(Session.self, from: data)
        }
    }

    func signIn(email: String, password: String) async throws {
        let response = try await tokenRequest(grantType: "password", body: ["email": email, "password": password])
        store(response)
    }

    func signOut() {
        session = nil
        keychain.delete()
    }

    /// A non-expired access token, refreshing it if it expires within a minute.
    func validAccessToken() async -> String? {
        guard let current = session else { return nil }
        if current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }

        // Coalesce concurrent refreshes into one request.
        if refreshTask == nil {
            refreshTask = Task { [weak self] in
                guard let self else { return nil }
                do {
                    let response = try await tokenRequest(grantType: "refresh_token", body: ["refresh_token": current.refreshToken])
                    store(response)
                } catch {
                    // A rejected refresh token means the session is dead.
                    if case AuthError.server = error { signOut() }
                }
                return session
            }
        }
        let refreshed = await refreshTask?.value
        refreshTask = nil
        return refreshed?.accessToken
    }

    // MARK: GoTrue

    private struct TokenResponse: Decodable {
        struct User: Decodable { let email: String? }
        let accessToken: String
        let refreshToken: String
        let expiresIn: Double
        let user: User?
    }

    private struct ErrorBody: Decodable {
        let msg: String?
        let errorDescription: String?
        let message: String?
        var text: String? { msg ?? errorDescription ?? message }
    }

    private func tokenRequest(grantType: String, body: [String: String]) async throws -> TokenResponse {
        let config = endpoint.config
        guard let supabaseURL = config.supabaseURL, let anonKey = config.supabaseAnonKey else {
            throw AuthError.notConfigured
        }
        var components = URLComponents(url: supabaseURL.appendingPathComponent("auth/v1/token"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: grantType)]
        guard let url = components?.url else { throw AuthError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // A server on the same Wi-Fi answers in well under a second; don't keep
        // the student waiting 20 s on an address that is gone.
        request.timeoutInterval = 8
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where Self.unreachableCodes.contains(error.code) {
            throw AuthError.unreachable(host: supabaseURL.host() ?? "the saved address")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            let message = (try? decoder.decode(ErrorBody.self, from: data))?.text
            throw AuthError.server(message ?? "Sign-in failed (\((response as? HTTPURLResponse)?.statusCode ?? -1)).")
        }
        return try decoder.decode(TokenResponse.self, from: data)
    }

    private func store(_ response: TokenResponse) {
        let newSession = Session(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: Date().addingTimeInterval(response.expiresIn),
            email: response.user?.email ?? session?.email,
        )
        session = newSession
        if let data = try? JSONEncoder().encode(newSession) {
            keychain.save(data)
        }
    }
}

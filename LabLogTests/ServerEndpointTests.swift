import XCTest
@testable import LabLog

/// Pointing the app at the backend on another address (Sync → Server).
final class ServerEndpointTests: XCTestCase {
    private let built = AppConfig(apiBaseURL: URL(string: "http://192.168.1.8:3100/api"),
                                  supabaseURL: URL(string: "http://192.168.1.8:54321"),
                                  supabaseAnonKey: "anon")

    func testReplacingHostKeepsSchemePortsAndPath() {
        let moved = built.replacingHost("172.20.10.2")
        XCTAssertEqual(moved.apiBaseURL?.absoluteString, "http://172.20.10.2:3100/api")
        XCTAssertEqual(moved.supabaseURL?.absoluteString, "http://172.20.10.2:54321")
        XCTAssertEqual(moved.supabaseAnonKey, "anon")
    }

    func testEndpointSwitchesAndGoesBack() {
        let endpoint = ServerEndpoint(built: built)
        endpoint.setHost("mac.local")
        XCTAssertEqual(endpoint.config.apiBaseURL?.host(), "mac.local")
        XCTAssertEqual(endpoint.defaultConfig.apiBaseURL?.host(), "192.168.1.8")
        endpoint.setHost(nil)
        XCTAssertEqual(endpoint.config.apiBaseURL?.host(), "192.168.1.8")
    }

    func testHostValidation() {
        for good in ["192.168.1.8", "172.20.10.2", "mac.local", "thanuras-macbook-pro.local", "localhost"] {
            XCTAssertTrue(AppConfig.isValidHost(good), good)
        }
        for bad in ["", "192.168.1", "300.1.1.1", "http://192.168.1.8", "my mac", "-bad.local", "a..b"] {
            XCTAssertFalse(AppConfig.isValidHost(bad), bad)
        }
    }

    /// An address where nothing answers (the Mac moved) fails fast with a
    /// message that says what to fix, not "The request timed out." (021).
    @MainActor
    func testSignInToAnAddressThatDoesNotAnswerSaysSo() async {
        let gone = AppConfig(apiBaseURL: URL(string: "http://127.0.0.1:9/api"),
                             supabaseURL: URL(string: "http://127.0.0.1:9"), supabaseAnonKey: "anon")
        let auth = AuthService(endpoint: ServerEndpoint(built: gone))
        do {
            try await auth.signIn(email: "student@lablog.test", password: "irrelevant")
            XCTFail("sign-in should fail")
        } catch let error as AuthService.AuthError {
            XCTAssertTrue(error.isUnreachable)
            XCTAssertEqual(error.errorDescription,
                           "Can't reach the server at 127.0.0.1. If your Mac's address has changed, update it below.")
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}

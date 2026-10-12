import Foundation

/// Build-time backend settings, read from Info.plist. Values come from
/// `Config/Secrets.xcconfig` (git-ignored); without it the app runs in
/// offline-only mode with the bundled catalog.
struct AppConfig {
    let apiBaseURL: URL?
    let supabaseURL: URL?
    let supabaseAnonKey: String?

    var isBackendConfigured: Bool {
        apiBaseURL != nil && supabaseURL != nil && supabaseAnonKey != nil
    }

    static func fromBundle(_ bundle: Bundle = .main) -> AppConfig {
        func value(_ key: String) -> String? {
            guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // Empty, or an unresolved "$(VAR)" when the xcconfig doesn't define it.
            guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
            return trimmed
        }
        return AppConfig(
            apiBaseURL: value("LabLogAPIBaseURL").flatMap(URL.init(string:)),
            supabaseURL: value("SupabaseURL").flatMap(URL.init(string:)),
            supabaseAnonKey: value("SupabaseAnonKey"),
        )
    }
}

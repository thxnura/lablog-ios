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

    /// The same backend reached at another address (the Mac's IP on a new
    /// Wi-Fi or hotspot). Scheme, ports and paths stay as built.
    func replacingHost(_ host: String) -> AppConfig {
        func swap(_ url: URL?) -> URL? {
            guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
            components.host = host
            return components.url ?? url
        }
        return AppConfig(apiBaseURL: swap(apiBaseURL), supabaseURL: swap(supabaseURL), supabaseAnonKey: supabaseAnonKey)
    }

    /// An IPv4 address or a host name such as `thanuras-macbook.local`.
    static func isValidHost(_ text: String) -> Bool {
        let host = text.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, host.count <= 253 else { return false }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        if parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) {
            return parts.count == 4 && parts.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
        }
        return parts.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && label.first != "-" && label.last != "-"
                && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}

import Foundation

/// Where the backend is. Starts as the build's `AppConfig`; the Sync tab can
/// point it at another host at runtime (the Mac's address on a hotspot at the
/// demo) without a rebuild. Read on every request, from any thread.
final class ServerEndpoint: @unchecked Sendable {
    private let lock = NSLock()
    private let built: AppConfig
    private var host: String?

    init(built: AppConfig, host: String? = nil) {
        self.built = built
        self.host = host
    }

    /// The build's own config (what "Use default" goes back to).
    var defaultConfig: AppConfig { built }

    var config: AppConfig {
        lock.withLock { host.map(built.replacingHost) ?? built }
    }

    /// nil → back to the build's address.
    func setHost(_ newHost: String?) {
        lock.withLock { host = newHost }
    }
}

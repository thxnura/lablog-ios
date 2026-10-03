import Foundation
import Network

/// Observes connectivity and publishes online/offline transitions. The
/// SyncEngine subscribes to `onBecameOnline` to flush the outbox.
@Observable
final class Reachability {
    private(set) var isOnline = true
    var onBecameOnline: () -> Void = {}

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "reachability")

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let nowOnline = path.status == .satisfied
            let wasOffline = !self.isOnline
            self.isOnline = nowOnline
            if nowOnline && wasOffline {
                DispatchQueue.main.async { self.onBecameOnline() }
            }
        }
        monitor.start(queue: queue)
    }

    func stop() { monitor.cancel() }
}

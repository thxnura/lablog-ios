import Foundation
import Network
import Observation

/// Observes connectivity and publishes online/offline transitions. The app
/// wires `onBecameOnline` to the SyncEngine so the outbox flushes on reconnect.
@MainActor
@Observable
final class Reachability {
    private(set) var isOnline = true

    @ObservationIgnored var onBecameOnline: () -> Void = {}
    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let queue = DispatchQueue(label: "com.thxnura.LabLog.reachability")
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        // NWPathMonitor calls back on its own queue; hop to the main actor
        // before touching observable state the UI reads.
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.update(online: online) }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
        started = false
    }

    private func update(online: Bool) {
        let wasOnline = isOnline
        isOnline = online
        if online && !wasOnline {
            onBecameOnline()
        }
    }
}

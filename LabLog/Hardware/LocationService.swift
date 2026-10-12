import CoreLocation

/// One-shot location fix used to stamp a lab record at submit time (authenticity:
/// "the student was in the lab"). Degrades gracefully: if permission is denied
/// or no fix arrives within the timeout, the record still submits with nil.
///
/// Requires `NSLocationWhenInUseUsageDescription` in Info.plist.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentCoordinate(timeout: Duration = .seconds(10)) async -> CLLocationCoordinate2D? {
        // One request at a time; a second caller just gets no fix.
        guard continuation == nil else { return nil }

        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.finish(nil)
        }
        defer { timeoutTask.cancel() }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            default:
                finish(nil)
            }
        }
    }

    private func finish(_ coordinate: CLLocationCoordinate2D?) {
        continuation?.resume(returning: coordinate)
        continuation = nil
    }

    // CLLocationManager delivers callbacks on the main run loop (it was created
    // on the main actor); the methods are nonisolated to satisfy the protocol.

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                if self.continuation != nil { self.manager.requestLocation() }
            case .denied, .restricted:
                self.finish(nil)
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        Task { @MainActor in self.finish(coordinate) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(nil) }
    }
}

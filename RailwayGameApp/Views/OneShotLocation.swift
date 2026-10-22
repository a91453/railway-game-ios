import CoreLocation
import GamePresentation

/// One fix of where the device is, for the real-world picker's "Use my
/// location" (ARCHITECTURE decision 332). It asks only for location while
/// the app is in use, asks once for one fix (`requestLocation`), never
/// tracks in the background, and keeps nothing: the caller moves the
/// picker's frame with the fix and drops it.
@MainActor
final class OneShotLocation: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    /// The ask in progress, answered once.
    private var pending: CheckedContinuation<MyLocationStart, Never>?
    /// Counts the asks, so a late time-out leaves a newer one alone.
    private var asks = 0
    /// How long an ask may take before it counts as failed, permission
    /// dialog included: the reference's `requestGeo` gives 12 s to the
    /// fix alone.
    private static let timeout: Duration = .seconds(30)

    override init() {
        super.init()
        manager.delegate = self
        // A town is enough to place a 16 km square, and comes sooner.
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Asks for the device's location once; asks the player first if they
    /// have not been asked.
    func locate() async -> MyLocationStart {
        // A second tap while one is under way waits for nothing new.
        guard pending == nil else { return .failed }
        asks += 1
        let ask = asks
        Task {
            try? await Task.sleep(for: Self.timeout)
            if asks == ask { finish(.failed) }
        }
        return await withCheckedContinuation { continuation in
            pending = continuation
            proceed()
        }
    }

    /// Goes on from the permission as it stands.
    private func proceed() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            finish(.denied)
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        @unknown default:
            finish(.failed)
        }
    }

    private func finish(_ result: MyLocationStart) {
        pending?.resume(returning: result)
        pending = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            // Also called when the manager is made; only an ask in
            // progress goes on.
            guard self.pending != nil, self.manager.authorizationStatus != .notDetermined else { return }
            self.proceed()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        let latitude = coordinate.latitude, longitude = coordinate.longitude
        Task { @MainActor in
            self.finish(.located(latitude: latitude, longitude: longitude))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        Task { @MainActor in
            self.finish(denied ? .denied : .failed)
        }
    }
}

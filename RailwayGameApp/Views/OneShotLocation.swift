import CoreLocation
import GamePresentation

/// One fix of where the device is, for the real-world picker's "Use my
/// location" (ARCHITECTURE decision 335). It asks only for location while
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
    /// What the last ask came to in detail, for a test build's line under
    /// the button (``MyLocationTrace``).
    private(set) var lastOutcome: MyLocationTrace.Outcome?
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
        lastOutcome = .locating
        asks += 1
        let ask = asks
        Task {
            try? await Task.sleep(for: Self.timeout)
            if asks == ask, pending != nil { finish(.failed, .timedOut(seconds: Int(Self.timeout.components.seconds))) }
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
            finish(.denied, .denied)
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        @unknown default:
            finish(.failed, .failed(code: -1, description: "unknown authorization"))
        }
    }

    private func finish(_ result: MyLocationStart, _ outcome: MyLocationTrace.Outcome) {
        guard pending != nil else { return }
        lastOutcome = outcome
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
        guard let location = locations.last else { return }
        let latitude = location.coordinate.latitude, longitude = location.coordinate.longitude
        let accuracy = location.horizontalAccuracy, age = -location.timestamp.timeIntervalSinceNow
        Task { @MainActor in
            self.finish(.located(latitude: latitude, longitude: longitude), .located(accuracyMetres: accuracy, ageSeconds: age))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        let code = (error as NSError).code, description = error.localizedDescription
        Task { @MainActor in
            self.finish(denied ? .denied : .failed, denied ? .denied : .failed(code: code, description: description))
        }
    }
}

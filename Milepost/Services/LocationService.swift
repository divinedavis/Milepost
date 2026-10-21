import CoreLocation
import Foundation
import Observation

/// Whether the phone has a fix good enough to record with. With no cell
/// service the phone has no network help finding satellites, so this can sit
/// on `.searching` for minutes; the screens say so instead of looking frozen.
enum GPSStatus: Equatable {
    case searching, ready

    /// Same cut-off the recorder uses: a fix it would throw away is no signal.
    static func of(_ location: CLLocation?) -> GPSStatus {
        guard let location, location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= RunRecorder.maxHorizontalAccuracy else { return .searching }
        return .ready
    }
}

/// Wraps CLLocationManager. During a run it streams continuous fixes with
/// background delivery on, which keeps the process alive with the screen off.
@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private(set) var authorization: CLAuthorizationStatus
    private(set) var lastLocation: CLLocation?
    private(set) var isTracking = false
    private(set) var lastError: String?
    /// True while the Record screen is up: updates run before Start so the
    /// GPS has locked by the time the runner taps it.
    private var isWarming = false

    var gpsStatus: GPSStatus { GPSStatus.of(lastLocation) }

    /// Every accepted fix, in delivery order. The recorder hangs off this.
    var onUpdate: (@MainActor (CLLocation) -> Void)?

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = kCLDistanceFilterNone
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    var isUndetermined: Bool { authorization == .notDetermined }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startTracking() {
        guard !isTracking else { return }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
        isTracking = true
    }

    func stopTracking() {
        guard isTracking else { return }
        if !isWarming { manager.stopUpdatingLocation() }
        manager.allowsBackgroundLocationUpdates = false
        isTracking = false
    }

    /// Foreground-only updates while the Record screen is showing. Never asks
    /// for permission; Start still does that.
    func warmUp() {
        guard isAuthorized, !isWarming else { return }
        isWarming = true
        if !isTracking { manager.startUpdatingLocation() }
    }

    func coolDown() {
        guard isWarming else { return }
        isWarming = false
        if !isTracking { manager.stopUpdatingLocation() }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.authorization = status }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations {
                self.lastLocation = location
                self.onUpdate?(location)
            }
            self.lastError = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.lastError = message }
    }
}

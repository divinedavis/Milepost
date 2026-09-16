import CoreLocation
import Foundation
import Observation

/// CoreLocation on the wrist.
///
/// Deliberately separate from the phone's `LocationService`: the watch has no
/// background location indicator to show, and it does not have to keep itself
/// alive — the running `HKWorkoutSession` does that, which is the whole reason
/// the workout session exists on watchOS. What is shared is the engine the
/// fixes are fed to, so pace and splits are computed identically on both.
@MainActor
@Observable
final class WatchLocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private(set) var authorization: CLAuthorizationStatus
    private(set) var lastLocation: CLLocation?
    private(set) var isTracking = false

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

    var isDenied: Bool { authorization == .denied || authorization == .restricted }
    var isUndetermined: Bool { authorization == .notDetermined }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startTracking() {
        guard !isTracking else { return }
        manager.startUpdatingLocation()
        isTracking = true
    }

    /// Turns on background delivery, which is what keeps fixes coming with the
    /// wrist down.
    ///
    /// This is deliberately **not** part of `startTracking`. Setting
    /// `allowsBackgroundLocationUpdates` on a process that is not backgroundable
    /// raises `NSInternalInconsistencyException` — "Invalid parameter not
    /// satisfying: !stayUp || CLClientIsBackgroundable(...)" — which is an
    /// Objective-C exception, so Swift cannot catch it and the app simply dies.
    /// On watchOS what makes the process backgroundable is a **running workout
    /// session**, so this is called once one has actually begun collecting, and
    /// never before.
    func allowBackgroundUpdates(_ allowed: Bool) {
        guard isBackgroundEligible || !allowed else { return }
        manager.allowsBackgroundLocationUpdates = allowed
    }

    /// Set by the controller when a workout session is live. Nothing else may
    /// turn background updates on.
    var isBackgroundEligible = false

    func stopTracking() {
        guard isTracking else { return }
        manager.stopUpdatingLocation()
        allowBackgroundUpdates(false)
        isBackgroundEligible = false
        isTracking = false
    }

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
        }
    }
}

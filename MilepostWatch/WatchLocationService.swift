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
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        isTracking = true
    }

    func stopTracking() {
        guard isTracking else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
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

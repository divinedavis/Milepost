#if DEBUG
import CoreLocation
import Foundation

/// Fills the watch screens with a plausible run so the UI can be seen and
/// captured without a wrist, a workout session or a GPS signal.
///
/// Debug only, and deliberately nowhere near HealthKit: it drives the real
/// `RunRecorder` with fabricated fixes, so what appears on screen is the app's
/// own arithmetic — real splits, a real pace from the per-sport bounds — rather
/// than hand-written numbers that would drift from the app the moment either
/// changed. watchOS has no XCUITest and the watch simulator's screenshots are
/// unreliable at the best of times, so this is the only way to look at these
/// screens at all.
@MainActor
enum WatchPreviewData {
    nonisolated static let launchArgument = "-watch-preview"

    nonisolated static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// Roughly 8:20 per mile: quick enough to look like a run, inside the run
    /// plausibility window so the pace renders instead of reading "-:--".
    private static let metersPerSecond: Double = 3.2
    private static let duration: TimeInterval = 12 * 60
    private static let baseLatitude = 40.6602
    private static let baseLongitude = -73.9690

    /// A recorder already twelve minutes into a run.
    ///
    /// The clock is injected and then moved: `start()` is called while the
    /// clock reads twelve minutes ago, and the offset is dropped afterwards, so
    /// the recorder genuinely believes it has been running that long. Nothing
    /// else can produce a running clock and a stack of finished splits.
    static func makeRecorder(sport: Sport = .run, unit: DistanceUnit = .miles) -> RunRecorder {
        var offset: TimeInterval = -duration
        let recorder = RunRecorder(now: { Date().addingTimeInterval(offset) })
        let start = Date().addingTimeInterval(-duration)
        recorder.start(unit: unit, sport: sport)

        // One fix every five seconds, running due north.
        let step: TimeInterval = 5
        var t: TimeInterval = 0
        while t <= duration {
            recorder.ingest(fix(secondsIn: t, from: start))
            t += step
        }
        offset = 0
        recorder.refreshElapsed()
        return recorder
    }

    private static func fix(secondsIn seconds: TimeInterval, from start: Date) -> CLLocation {
        let metersNorth = metersPerSecond * seconds
        // Metres per degree of latitude, near enough at this latitude.
        let latitude = baseLatitude + metersNorth / 111_320
        return CLLocation(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: baseLongitude),
                          altitude: 12,
                          horizontalAccuracy: 5,
                          verticalAccuracy: 4,
                          course: 0,
                          speed: metersPerSecond,
                          timestamp: start.addingTimeInterval(seconds))
    }

    /// Heart rate and calories a watch would have measured over that run.
    static let heartRate: Double = 156
    static let averageHeartRate: Double = 148
    static let maxHeartRate: Double = 171
    static let activeKilocalories: Double = 214
}
#endif

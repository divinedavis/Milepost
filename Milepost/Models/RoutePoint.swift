import CoreLocation
import Foundation

struct RoutePoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
    /// Altitude and fix quality, kept so the route written to Apple Health is
    /// a real CLLocation rather than a bare coordinate, and so elevation gain
    /// can be measured. All optional: activities recorded before Health
    /// support decode unchanged, with nil here.
    var altitude: Double?
    var horizontalAccuracy: Double?
    var verticalAccuracy: Double?
    var speed: Double?
    /// Distance the recorder had booked when this fix was accepted. Consecutive
    /// route points cannot be measured against each other to get this: the gap
    /// across a pause covers ground the recorder deliberately never counted.
    /// Optional for the same reason as the fields above.
    var cumulativeMeters: Double?

    init(latitude: Double, longitude: Double, timestamp: Date,
         altitude: Double? = nil, horizontalAccuracy: Double? = nil,
         verticalAccuracy: Double? = nil, speed: Double? = nil,
         cumulativeMeters: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.verticalAccuracy = verticalAccuracy
        self.speed = speed
        self.cumulativeMeters = cumulativeMeters
    }

    init(_ location: CLLocation, cumulativeMeters: Double? = nil) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        timestamp = location.timestamp
        altitude = location.altitude
        horizontalAccuracy = location.horizontalAccuracy
        verticalAccuracy = location.verticalAccuracy
        speed = location.speed
        self.cumulativeMeters = cumulativeMeters
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// HealthKit refuses route points with a non-positive horizontal accuracy,
    /// so a point stored before the field existed reports the worst fix the
    /// engine would ever have accepted — an honest upper bound, not a guess at
    /// a better one. A nil altitude is published with an invalid vertical
    /// accuracy, which is how CoreLocation says "no altitude".
    var location: CLLocation {
        CLLocation(coordinate: coordinate,
                   altitude: altitude ?? 0,
                   horizontalAccuracy: horizontalAccuracy ?? RunRecorder.maxHorizontalAccuracy,
                   verticalAccuracy: altitude == nil ? -1 : (verticalAccuracy ?? -1),
                   course: -1,
                   speed: speed ?? -1,
                   timestamp: timestamp)
    }
}

/// One unit of distance (mile or km) of a run. The last split of a run in
/// progress is partial; `isComplete` tells the bar chart which is which.
struct Split: Codable, Hashable, Identifiable {
    var index: Int
    var distanceMeters: Double
    var seconds: TimeInterval

    var id: Int { index }

    func isComplete(splitMeters: Double) -> Bool {
        distanceMeters >= splitMeters - 0.001
    }

    func pace(unit: DistanceUnit, sport: Sport = .run) -> Double? {
        Pace.secondsPerUnit(distanceMeters: distanceMeters, seconds: seconds, unit: unit, sport: sport)
    }
}

extension Array where Element == Split {
    /// The best pace over a full split, which is what "fastest pace" means on
    /// Nike Run Club and Strava's "best mile". A split still in progress is
    /// never counted: a 40 m opening sprint would otherwise be the fastest
    /// pace of every run. Nil until the first split completes.
    func fastestPace(splitMeters: Double, unit: DistanceUnit, sport: Sport = .run) -> Double? {
        filter { $0.isComplete(splitMeters: splitMeters) }
            .compactMap { $0.pace(unit: unit, sport: sport) }
            .min()
    }

    /// The index of the split `fastestPace` came from, for marking it in a list.
    func fastestIndex(splitMeters: Double, unit: DistanceUnit, sport: Sport = .run) -> Int? {
        guard let best = fastestPace(splitMeters: splitMeters, unit: unit, sport: sport) else { return nil }
        return first { $0.isComplete(splitMeters: splitMeters) && $0.pace(unit: unit, sport: sport) == best }?.index
    }
}

/// A stretch of a recording where the clock was stopped. Apple Health derives
/// a workout's duration from pause/resume events, so without these Health
/// would show elapsed time where Milepost shows moving time.
struct PauseInterval: Codable, Hashable {
    var start: Date
    var end: Date?

    var duration: TimeInterval { (end ?? start).timeIntervalSince(start) }
}

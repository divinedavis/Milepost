import CoreLocation
import Foundation

struct RoutePoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var timestamp: Date

    init(latitude: Double, longitude: Double, timestamp: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }

    init(_ location: CLLocation) {
        latitude = location.coordinate.latitude
        longitude = location.coordinate.longitude
        timestamp = location.timestamp
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
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

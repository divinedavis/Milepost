import CoreLocation
import Foundation
import SwiftData

@Model
final class Activity {
    @Attribute(.unique) var id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    /// Time the clock was running, excluding pauses.
    var movingSeconds: TimeInterval
    var distanceMeters: Double
    /// The split length this run was recorded with, so the stored splits stay
    /// meaningful if the unit setting changes later.
    var splitMeters: Double
    var routeData: Data
    var splitsData: Data
    /// Added after 1.0 shipped. The default is what every stored activity
    /// was, so SwiftData migrates old rows without touching them.
    var sportRaw: String = Sport.run.rawValue

    init(id: UUID = UUID(),
         title: String,
         startDate: Date,
         endDate: Date,
         movingSeconds: TimeInterval,
         distanceMeters: Double,
         splitMeters: Double,
         route: [RoutePoint],
         splits: [Split],
         sport: Sport = .run) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.movingSeconds = movingSeconds
        self.distanceMeters = distanceMeters
        self.splitMeters = splitMeters
        self.routeData = (try? JSONEncoder().encode(route)) ?? Data()
        self.splitsData = (try? JSONEncoder().encode(splits)) ?? Data()
        self.sportRaw = sport.rawValue
    }

    convenience init(summary: RunSummary, title: String) {
        self.init(title: title,
                  startDate: summary.startDate,
                  endDate: summary.endDate,
                  movingSeconds: summary.movingSeconds,
                  distanceMeters: summary.distanceMeters,
                  splitMeters: summary.splitMeters,
                  route: summary.route,
                  splits: summary.splits,
                  sport: summary.sport)
    }

    var route: [RoutePoint] {
        (try? JSONDecoder().decode([RoutePoint].self, from: routeData)) ?? []
    }

    var splits: [Split] {
        (try? JSONDecoder().decode([Split].self, from: splitsData)) ?? []
    }

    var sport: Sport { Sport(rawValue: sportRaw) ?? .run }

    var recordedUnit: DistanceUnit {
        abs(splitMeters - DistanceUnit.kilometers.meters) < 1 ? .kilometers : .miles
    }

    var coordinates: [CLLocationCoordinate2D] { route.map(\.coordinate) }

    func averagePace(unit: DistanceUnit) -> Double? {
        Pace.secondsPerUnit(distanceMeters: distanceMeters, seconds: movingSeconds, unit: unit, sport: sport)
    }
}

struct ActivityTotals: Equatable {
    var count = 0
    var distanceMeters = 0.0
    var seconds: TimeInterval = 0

    func averagePace(unit: DistanceUnit) -> Double? {
        Pace.secondsPerUnit(distanceMeters: distanceMeters, seconds: seconds, unit: unit)
    }
}

enum ActivityStats {
    static func totals(_ activities: [Activity], in interval: DateInterval? = nil) -> ActivityTotals {
        var t = ActivityTotals()
        for a in activities {
            if let interval, !interval.contains(a.startDate) { continue }
            t.count += 1
            t.distanceMeters += a.distanceMeters
            t.seconds += a.movingSeconds
        }
        return t
    }

    static func thisWeek(_ activities: [Activity], now: Date = .now, calendar: Calendar = .current) -> ActivityTotals {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return totals(activities) }
        return totals(activities, in: week)
    }
}

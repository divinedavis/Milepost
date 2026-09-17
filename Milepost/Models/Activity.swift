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
    /// The UUID of the workout this activity was written to in Apple Health,
    /// or nil if it was never written. Added after 1.0 with a default, so
    /// SwiftData migrates stored activities without a mapping model.
    var healthWorkoutID: String? = nil
    /// Pauses, for re-writing this activity to Health later. Stored as JSON
    /// with an empty default for the same migration reason.
    var pausesData: Data = Data()

    init(id: UUID = UUID(),
         title: String,
         startDate: Date,
         endDate: Date,
         movingSeconds: TimeInterval,
         distanceMeters: Double,
         splitMeters: Double,
         route: [RoutePoint],
         splits: [Split],
         sport: Sport = .run,
         pauses: [PauseInterval] = []) {
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
        self.pausesData = (try? JSONEncoder().encode(pauses)) ?? Data()
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
                  sport: summary.sport,
                  pauses: summary.pauses)
    }

    var route: [RoutePoint] {
        (try? JSONDecoder().decode([RoutePoint].self, from: routeData)) ?? []
    }

    var splits: [Split] {
        (try? JSONDecoder().decode([Split].self, from: splitsData)) ?? []
    }

    var sport: Sport { Sport(rawValue: sportRaw) ?? .run }

    var pauses: [PauseInterval] {
        (try? JSONDecoder().decode([PauseInterval].self, from: pausesData)) ?? []
    }

    var isInAppleHealth: Bool { healthWorkoutID != nil }

    /// The activity as the recorder would have handed it over, so the Health
    /// writer has one input whether it is called at save time or later.
    var summary: RunSummary {
        RunSummary(startDate: startDate,
                   endDate: endDate,
                   movingSeconds: movingSeconds,
                   distanceMeters: distanceMeters,
                   splitMeters: splitMeters,
                   route: route,
                   splits: splits,
                   sport: sport,
                   pauses: pauses)
    }

    var recordedUnit: DistanceUnit {
        abs(splitMeters - DistanceUnit.kilometers.meters) < 1 ? .kilometers : .miles
    }

    var coordinates: [CLLocationCoordinate2D] { route.map(\.coordinate) }

    func averagePace(unit: DistanceUnit) -> Double? {
        Pace.secondsPerUnit(distanceMeters: distanceMeters, seconds: movingSeconds, unit: unit, sport: sport)
    }

    /// Best full split, in the unit the activity was recorded in — splits
    /// cannot be re-cut to another unit after the fact.
    var fastestSplitPace: Double? {
        splits.fastestPace(splitMeters: splitMeters, unit: recordedUnit, sport: sport)
    }

    var fastestSplitIndex: Int? {
        splits.fastestIndex(splitMeters: splitMeters, unit: recordedUnit, sport: sport)
    }

    /// Derived from the stored route on every read rather than stored: the
    /// rule can improve without a migration, and it stays identical to what
    /// Health was told.
    var elevationGainMeters: Double? {
        SplitTimeline.elevationAscended(route: route)
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

import CoreLocation
import Foundation
import HealthKit

/// A walk, run or ride another app saved to Apple Health with its GPS route
/// (Apple's Workout app, Strava, Nike Run Club...), drawn on "Your map"
/// beside Milepost's own (added 2026-10-23, owner request). Read only, kept
/// in memory, never stored or uploaded.
struct HealthRoute: Identifiable {
    let id: UUID
    let sport: Sport
    let start: Date
    /// `HKMetadataKeyExternalUUID`: Milepost puts its activity id there.
    let externalID: String?
    let brand: String?
    /// Already thinned to `RouteLine.maxPoints`.
    let coordinates: [CLLocationCoordinate2D]
}

enum HealthRouteRules {
    /// A year of workouts, newest first, at most this many.
    static let windowDays = 365
    static let maxWorkouts = 300
    /// The same outing recorded by Milepost and by another app (a Watch's
    /// Workout app running alongside) starts within a couple of minutes.
    static let sameOutingSeconds: TimeInterval = 120
    /// A loaded list is reused this long before Health is asked again.
    static let refreshSeconds: TimeInterval = 600

    static let workoutTypes: [HKWorkoutActivityType] = [.running, .walking, .hiking, .cycling]

    static func sport(for type: HKWorkoutActivityType) -> Sport? {
        switch type {
        case .running: return .run
        case .walking, .hiking: return .walk
        case .cycling: return .bike
        default: return nil
        }
    }

    /// Milepost's own workouts (phone or watch) are already on the map as
    /// activities, and so is anything that started with one of them.
    static func isAlreadyOnMap(_ route: HealthRoute, activities: [Activity]) -> Bool {
        if route.brand == "Milepost" { return true }
        return activities.contains { activity in
            activity.healthWorkoutID == route.id.uuidString
                || activity.id.uuidString == route.externalID
                || abs(activity.startDate.timeIntervalSince(route.start)) <= sameOutingSeconds
        }
    }

    static func newRoutes(_ routes: [HealthRoute], activities: [Activity]) -> [HealthRoute] {
        routes.filter { !isAlreadyOnMap($0, activities: activities) }
    }

    #if DEBUG
    /// `-uitest-health-routes`: a run and a ride "from another app" near the
    /// simulator's pinned fix, so the map can be tested without Health.
    static func demo(now: Date = .now) -> [HealthRoute] {
        let run = [(40.6835, -73.9680), (40.6760, -73.9700), (40.6745, -73.9630), (40.6835, -73.9680)]
        let ride = [(40.6900, -73.9600), (40.7000, -73.9550), (40.7050, -73.9700)]
        return [
            HealthRoute(id: UUID(), sport: .run, start: now.addingTimeInterval(-3 * 86_400),
                        externalID: nil, brand: nil, coordinates: run.map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }),
            HealthRoute(id: UUID(), sport: .bike, start: now.addingTimeInterval(-12 * 86_400),
                        externalID: nil, brand: nil, coordinates: ride.map { CLLocationCoordinate2D(latitude: $0.0, longitude: $0.1) }),
        ]
    }
    #endif
}

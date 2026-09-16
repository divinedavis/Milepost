import HealthKit

/// The Health mapping lives here, not on `Sport`, because `Sport` is compiled
/// into the widget extension and must stay free of frameworks the widget has
/// no business linking.
extension Sport {
    var workoutActivityType: HKWorkoutActivityType {
        switch self {
        case .run, .strollerRun: return .running
        case .walk: return .walking
        case .bike: return .cycling
        }
    }

    /// The cumulative distance type Health files this sport's mileage under.
    /// A ride counts as cycling distance; everything else as walking+running,
    /// which is the type the Fitness app's distance figure reads.
    var distanceQuantityType: HKQuantityType {
        switch self {
        case .bike: return HKQuantityType(.distanceCycling)
        case .run, .strollerRun, .walk: return HKQuantityType(.distanceWalkingRunning)
        }
    }

    /// Health has no stroller running, so it is filed as a run and the
    /// distinction is carried in workout metadata instead of being lost.
    var healthBrandMetadata: [String: Any] {
        self == .strollerRun ? [HKMetadataKeyWorkoutBrandName: "Milepost Stroller Run"] : [:]
    }
}

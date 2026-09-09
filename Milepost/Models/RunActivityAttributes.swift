import ActivityKit
import Foundation

/// What the Live Activity (Dynamic Island + lock screen) knows about the run
/// in progress. Compiled into both the app and the widget extension, so it
/// must stay free of anything app-only (no RunRecorder, no SwiftData).
struct RunActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The clock ticks on its own inside the widget: while recording it
        /// counts up from an anchor, so the app does not have to push an
        /// update every second.
        enum Clock: Codable, Hashable {
            case running(since: Date)
            case paused(elapsed: TimeInterval)
        }

        /// Distance in the run's unit, rounded to what is displayed (0.01),
        /// so a tick that changes nothing visible is not an update.
        var distanceUnits: Double
        var clock: Clock
        /// 1-based number of the mile / kilometer the runner is on.
        var splitIndex: Int
        /// 0…1 progress through that mile / kilometer, rounded to 0.01.
        var splitFraction: Double
        /// Whole seconds per unit for the split in progress; nil until it
        /// means something (under 10 m in, or a pace outside running range).
        var splitPace: Double?
        /// The pace of the last *completed* split, shown while the one in
        /// progress has no pace yet. Deliberately not the run average: the
        /// average drifts every second, which would make every idle tick a
        /// push. Both of these only move when a GPS fix lands.
        var previousSplitPace: Double?

        var isPaused: Bool {
            if case .paused = clock { return true }
            return false
        }
    }

    /// Fixed for the life of the run.
    var unitRaw: String
    var startDate: Date

    var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .miles }

    init(unit: DistanceUnit, startDate: Date) {
        unitRaw = unit.rawValue
        self.startDate = startDate
    }
}

extension RunActivityAttributes.ContentState {
    /// "Mile 3" / "Kilometer 3": the headline everywhere.
    func headline(unit: DistanceUnit) -> String {
        "\(unit.splitNoun) \(splitIndex)"
    }

    /// "2.41 mi · 9:12 /mi": total distance and the pace of the split in
    /// progress, falling back to the run average while the split is too
    /// young to have one.
    func subtitle(unit: DistanceUnit) -> String {
        let distance = "\(Format.distance(distanceUnits * unit.meters, unit: unit)) \(unit.abbreviation)"
        if let pace = splitPace ?? previousSplitPace {
            return "\(distance) · \(Format.pace(pace)) \(unit.paceSuffix)"
        }
        return distance
    }

    /// "Mile 4": where the progress bar is heading.
    func nextHeadline(unit: DistanceUnit) -> String {
        "\(unit.splitNoun) \(splitIndex + 1)"
    }
}

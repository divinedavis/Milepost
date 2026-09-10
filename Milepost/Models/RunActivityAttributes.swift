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
    var sportRaw: String
    var startDate: Date

    var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .miles }
    var sport: Sport { Sport(rawValue: sportRaw) ?? .run }

    init(unit: DistanceUnit, sport: Sport, startDate: Date) {
        unitRaw = unit.rawValue
        sportRaw = sport.rawValue
        self.startDate = startDate
    }
}

extension RunActivityAttributes.ContentState {
    /// "0.30 mi" — how far so far. This is the number that actually moves,
    /// so it is the headline everywhere; the mile you are *on* only changes
    /// once a mile and reads as stuck. Two decimals under 10 units and one
    /// above, so the compact island never runs out of room.
    func distanceText(unit: DistanceUnit) -> String {
        let number = distanceUnits >= 10
            ? String(format: "%.1f", distanceUnits)
            : String(format: "%.2f", distanceUnits)
        return "\(number) \(unit.abbreviation)"
    }

    /// "Mile 3": the mile / kilometer in progress.
    func splitText(unit: DistanceUnit) -> String {
        "\(unit.splitNoun) \(splitIndex)"
    }

    /// "Mile 3 · 9:12 /mi", or "Mile 3 · 14.2 mph" on a ride. The rate is the
    /// split in progress, falling back to the last finished split while this
    /// one is too young to have one.
    func detailText(unit: DistanceUnit, sport: Sport = .run) -> String {
        let split = splitText(unit: unit)
        if let rate = splitPace ?? previousSplitPace {
            return "\(split) · \(sport.rateText(rate, unit: unit)) \(sport.rateSuffix(unit: unit))"
        }
        return split
    }

    /// What VoiceOver reads off the track.
    func trackDescription(unit: DistanceUnit) -> String {
        let percent = Int((splitFraction * 100).rounded())
        return "\(percent) percent to \(unit.splitNoun) \(splitIndex + 1)"
    }
}

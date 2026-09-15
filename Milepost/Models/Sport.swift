import Foundation

/// What is being recorded. The engine is the same for every sport — GPS in,
/// distance and splits out — but what counts as a plausible speed and how
/// the rate is phrased differ. Compiled into the widget too, so it must
/// stay free of app-only types.
enum Sport: String, CaseIterable, Identifiable, Codable {
    case run, strollerRun, walk, bike

    static let storageKey = "sport"

    var id: String { rawValue }

    /// Cycling is a "ride", not a "bike".
    var title: String {
        switch self {
        case .run: return "Run"
        case .strollerRun: return "Stroller Run"
        case .walk: return "Walk"
        case .bike: return "Ride"
        }
    }

    /// A nil system symbol uses the custom drawing in SportIcon.
    var symbol: String? {
        switch self {
        case .run: return "figure.run"
        case .strollerRun: return nil
        case .walk: return "figure.walk"
        case .bike: return "bicycle"
        }
    }

    /// What the picker says under the title. Kept short enough for one line
    /// on the narrowest phone, and free of a unit — the Units setting decides
    /// whether that pace is per mile or per kilometer.
    var subtitle: String {
        switch self {
        case .run: return "Pace, splits and voice cues"
        case .strollerRun: return "Running with a stroller"
        case .walk: return "Pace, at walking speeds"
        case .bike: return "Speed instead of pace"
        }
    }

    /// Nobody reads a bike ride in minutes per mile; cyclists think in mph.
    var showsSpeed: Bool { self == .bike }

    /// "pace" or "speed" — the word used in every label.
    var rateNoun: String { showsSpeed ? "speed" : "pace" }

    // Plausibility bounds, in seconds per unit, for the rate this sport
    // records. Anything outside reads as "-:--" rather than a nonsense
    // number from GPS jitter — a walk can be slower than a run ever is, and
    // a descent on a bike is faster than any run.
    var fastestSecondsPerUnit: Double {
        switch self {
        case .run, .strollerRun: return 2 * 60      // 30 mph
        case .walk: return 6 * 60     // 10 mph, about a race walk
        case .bike: return 80         // 45 mph
        }
    }

    var slowestSecondsPerUnit: Double {
        switch self {
        case .run, .strollerRun: return 40 * 60
        case .walk: return 60 * 60    // 1 mph, a genuine stroll
        case .bike: return 20 * 60    // 3 mph
        }
    }

    /// "9:12" for a run or walk, "14.2" for a ride.
    func rateText(_ secondsPerUnit: Double?, unit: DistanceUnit) -> String {
        showsSpeed ? Format.speed(secondsPerUnit) : Format.pace(secondsPerUnit)
    }

    /// "/mi" or "mph".
    func rateSuffix(unit: DistanceUnit) -> String {
        showsSpeed ? unit.speedAbbreviation : unit.paceSuffix
    }

    /// "Avg. pace (/mi)" / "Avg. speed (mph)".
    func rateLabel(_ prefix: String, unit: DistanceUnit) -> String {
        "\(prefix) \(rateNoun) (\(rateSuffix(unit: unit)))"
    }

    /// How the voice says it: "Average pace, 9 minutes 12 seconds per mile."
    /// or "Average speed, 14.2 miles per hour."
    func spokenRate(_ secondsPerUnit: Double, unit: DistanceUnit) -> String {
        if showsSpeed {
            return "Average speed, \(Format.speed(secondsPerUnit)) \(unit.speedSpokenSuffix)."
        }
        return "Average pace, \(Format.spokenDuration(secondsPerUnit)) per \(unit.splitNoun.lowercased())."
    }
}

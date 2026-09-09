import Foundation

/// How often the recorder speaks a progress update mid-run. Stored in
/// UserDefaults; read live, so changing it during a run takes effect at the
/// next milestone.
enum VoiceCueInterval: String, CaseIterable, Identifiable {
    case off, full, half

    static let storageKey = "voiceCues"

    var id: String { rawValue }

    func title(unit: DistanceUnit) -> String {
        let noun = unit.splitNoun.lowercased()
        switch self {
        case .off: return "Off"
        case .full: return "Every \(noun)"
        case .half: return "Every half \(noun)"
        }
    }

    /// Whether a milestone at `units` (0.5, 1, 1.5, …) should be spoken.
    func includes(units: Double) -> Bool {
        switch self {
        case .off: return false
        case .full: return units == units.rounded(.down)
        case .half: return true
        }
    }
}

/// A half-unit boundary the run just crossed, with the moving time at the
/// crossing (pro-rated inside the GPS step, like splits are).
struct Milestone: Equatable {
    var distanceMeters: Double
    var elapsed: TimeInterval
    var unit: DistanceUnit
    var sport: Sport = .run

    /// 0.5, 1, 1.5, … in the run's unit.
    var units: Double { (distanceMeters / unit.meters * 2).rounded() / 2 }

    var averagePace: Double? {
        Pace.secondsPerUnit(distanceMeters: distanceMeters, seconds: elapsed, unit: unit, sport: sport)
    }
}

/// Turns a milestone into what the voice says. Kept as plain text so it is
/// testable without a synthesizer.
enum VoiceCuePhrase {
    static func text(for m: Milestone) -> String {
        var parts = [distance(m.units, unit: m.unit)]
        parts.append("Time, \(spoken(seconds: m.elapsed)).")
        if let pace = m.averagePace {
            parts.append(m.sport.spokenRate(pace, unit: m.unit))
        }
        return parts.joined(separator: " ")
    }

    static func distance(_ units: Double, unit: DistanceUnit) -> String {
        let whole = Int(units.rounded(.down))
        let hasHalf = units - Double(whole) >= 0.25
        let noun = unit.splitNoun.lowercased()
        switch (whole, hasHalf) {
        case (0, true): return "Half \(noun)."
        case (1, false): return "One \(noun)."
        case (let n, false): return "\(n) \(noun)s."
        case (let n, true): return "\(n) and a half \(noun)s."
        }
    }

    /// "9 minutes 5 seconds", "1 hour 2 minutes", "45 seconds".
    static func spoken(seconds: TimeInterval) -> String { Format.spokenDuration(seconds) }
}

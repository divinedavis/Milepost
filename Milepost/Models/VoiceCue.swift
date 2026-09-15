import Foundation

/// How often the recorder speaks a progress update mid-run. Stored in
/// UserDefaults; read live, so changing it during a run takes effect at the
/// next milestone.
enum VoiceCueInterval: String, CaseIterable, Identifiable {
    // `off` remains readable for settings saved by earlier versions.
    case off, full, half, two, five

    static let storageKey = "voiceCues"
    static let enabledKey = "voiceCuesEnabled"
    static let selectable: [Self] = [.half, .full, .two, .five]

    var id: String { rawValue }

    func title(unit: DistanceUnit) -> String {
        let noun = unit.splitNoun.lowercased()
        switch self {
        case .off: return "Off"
        case .full: return "Every \(noun)"
        case .half: return "Every half \(noun)"
        case .two: return "Every 2 \(noun)s"
        case .five: return "Every 5 \(noun)s"
        }
    }

    var units: Double {
        switch self {
        case .off, .half: return 0.5
        case .full: return 1
        case .two: return 2
        case .five: return 5
        }
    }

    /// Split the old Off/interval preference without losing an explicit opt-out.
    /// New installs announce every half unit; existing selections are kept.
    static func migrateSettings(in defaults: UserDefaults) {
        let previous = defaults.string(forKey: storageKey).flatMap(Self.init(rawValue:))
        if defaults.object(forKey: enabledKey) == nil {
            defaults.set(previous != .off, forKey: enabledKey)
        }
        if previous == nil || previous == .off {
            defaults.set(Self.half.rawValue, forKey: storageKey)
        }
    }

    /// Whether a milestone at `units` (0.5, 1, 1.5, …) should be spoken.
    func includes(units: Double) -> Bool {
        guard self != .off, units.isFinite, units > 0 else { return false }
        return units.truncatingRemainder(dividingBy: self.units) == 0
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
        case (0, true): return "Half a \(noun) complete."
        case (1, false): return "1 \(noun) complete."
        case (let n, false): return "\(n) \(noun)s complete."
        case (let n, true): return "\(n) and a half \(noun)s complete."
        }
    }

    /// "9 minutes 5 seconds", "1 hour 2 minutes", "45 seconds".
    static func spoken(seconds: TimeInterval) -> String { Format.spokenDuration(seconds) }
}

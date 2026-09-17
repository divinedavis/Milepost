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

/// The same cue as a list of recorded clips.
///
/// The voice is rendered once, at build time, by `scripts/make_voice_cues.py`
/// and shipped as short clips: the app never calls a speech API, so no key
/// travels in the bundle, a run in a park with one bar still gets its cues,
/// and the render is paid for once rather than per mile. A cue is stitched
/// from a whole distance phrase ("1 mile complete.") followed by number and
/// word clips for the time and the pace, which is the only way a value that
/// changes every run can come out of a fixed library.
///
/// `library` is the single list of everything that can be said; the render
/// script writes the same list to `VoiceCues.json` and a test checks the two
/// have not drifted apart.
enum VoiceCueScript {
    static let clipPrefix = "cue_"
    static let manifestName = "VoiceCues"
    /// Past this the distance phrase falls back to the system voice. Thirty
    /// miles / fifty kilometers covers a marathon with room to spare.
    static func maxWholeUnits(_ unit: DistanceUnit) -> Int { unit == .miles ? 30 : 50 }

    /// Clip names, in speaking order, or nil when the library cannot say this
    /// milestone and the caller should synthesize `VoiceCuePhrase.text` instead.
    static func clips(for m: Milestone) -> [String]? {
        guard let distance = distanceClip(m.units, unit: m.unit),
              let time = durationClips(m.elapsed) else { return nil }
        var out = [distance, "phrase_time"] + time
        if let pace = m.averagePace {
            guard let rate = rateClips(pace, unit: m.unit, sport: m.sport) else { return nil }
            out += rate
        }
        return out
    }

    static func distanceClip(_ units: Double, unit: DistanceUnit) -> String? {
        guard units.isFinite, units > 0 else { return nil }
        let whole = Int(units.rounded(.down))
        let hasHalf = units - Double(whole) >= 0.25
        guard whole <= maxWholeUnits(unit) else { return nil }
        return "dist_\(unit.abbreviation)_\(whole)\(hasHalf ? "h" : "")"
    }

    /// "9 minutes 5 seconds" as number + word clips, mirroring
    /// `Format.spokenDuration` exactly so the fallback says the same thing.
    static func durationClips(_ seconds: TimeInterval) -> [String]? {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        guard h <= 59 else { return nil }
        var out: [String] = []
        if h > 0 { out += ["num_\(h)", h == 1 ? "word_hour" : "word_hours"] }
        if m > 0 { out += ["num_\(m)", m == 1 ? "word_minute" : "word_minutes"] }
        if s > 0 || out.isEmpty { out += ["num_\(s)", s == 1 ? "word_second" : "word_seconds"] }
        return out
    }

    /// "Average pace, 9 minutes 12 seconds per mile." or
    /// "Average speed, 14 point 2 miles per hour."
    static func rateClips(_ secondsPerUnit: Double, unit: DistanceUnit, sport: Sport) -> [String]? {
        if sport.showsSpeed {
            let parts = Format.speed(secondsPerUnit).split(separator: ".")
            guard parts.count == 2, let whole = Int(parts[0]), let tenth = Int(parts[1]), whole <= 59 else { return nil }
            var out = ["phrase_avg_speed", "num_\(whole)"]
            if tenth > 0 { out += ["word_point", "num_\(tenth)"] }
            out.append(unit == .miles ? "unit_mph" : "unit_kmh")
            return out
        }
        guard let time = durationClips(secondsPerUnit) else { return nil }
        return ["phrase_avg_pace"] + time + [unit == .miles ? "unit_per_mi" : "unit_per_km"]
    }

    /// Every clip name with the text it was rendered from.
    static var library: [String: String] {
        var out: [String: String] = [:]
        for unit in DistanceUnit.allCases {
            out["dist_\(unit.abbreviation)_0h"] = VoiceCuePhrase.distance(0.5, unit: unit)
            for n in 1...maxWholeUnits(unit) {
                out["dist_\(unit.abbreviation)_\(n)"] = VoiceCuePhrase.distance(Double(n), unit: unit)
                out["dist_\(unit.abbreviation)_\(n)h"] = VoiceCuePhrase.distance(Double(n) + 0.5, unit: unit)
            }
        }
        for n in 0...59 { out["num_\(n)"] = "\(n)" }
        out["phrase_time"] = "Time,"
        out["phrase_avg_pace"] = "Average pace,"
        out["phrase_avg_speed"] = "Average speed,"
        out["word_hour"] = "hour"
        out["word_hours"] = "hours"
        out["word_minute"] = "minute"
        out["word_minutes"] = "minutes"
        out["word_second"] = "second"
        out["word_seconds"] = "seconds"
        out["word_point"] = "point"
        out["unit_per_mi"] = "per mile."
        out["unit_per_km"] = "per kilometer."
        out["unit_mph"] = "miles per hour."
        out["unit_kmh"] = "kilometers per hour."
        return out
    }

    /// What `scripts/make_voice_cues.py` writes next to the clips.
    struct Manifest: Codable, Equatable {
        var voiceID: String
        var voiceName: String
        var modelID: String
        var clips: [String: String]
    }
}

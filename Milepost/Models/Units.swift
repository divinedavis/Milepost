import Foundation

enum DistanceUnit: String, CaseIterable, Identifiable {
    case miles, kilometers

    static let storageKey = "distanceUnit"

    var id: String { rawValue }
    var meters: Double { self == .miles ? 1609.344 : 1000 }
    var abbreviation: String { self == .miles ? "mi" : "km" }
    var title: String { self == .miles ? "Miles" : "Kilometers" }
    var paceSuffix: String { "/\(abbreviation)" }
    var splitNoun: String { self == .miles ? "Mile" : "Kilometer" }
    var speedAbbreviation: String { self == .miles ? "mph" : "km/h" }
    var speedSpokenSuffix: String { self == .miles ? "miles per hour" : "kilometers per hour" }
}

/// Pace is seconds per unit distance. Anything outside a plausible range for
/// the sport reads as "-:--" instead of a nonsense number from GPS jitter.
/// A ride divides the same number differently — see `Format.speed`.
enum Pace {
    static let fastestSecondsPerUnit: Double = Sport.run.fastestSecondsPerUnit
    static let slowestSecondsPerUnit: Double = Sport.run.slowestSecondsPerUnit
    static let minimumDistanceMeters: Double = 10

    static func secondsPerUnit(distanceMeters: Double, seconds: TimeInterval,
                               unit: DistanceUnit, sport: Sport = .run) -> Double? {
        guard distanceMeters >= minimumDistanceMeters, seconds > 0 else { return nil }
        let pace = seconds / (distanceMeters / unit.meters)
        guard pace >= sport.fastestSecondsPerUnit, pace <= sport.slowestSecondsPerUnit else { return nil }
        return pace
    }
}

enum Format {
    static func distance(_ meters: Double, unit: DistanceUnit) -> String {
        String(format: "%.2f", meters / unit.meters)
    }

    /// The same number a pace is built from, read the other way round:
    /// units per hour, to one decimal. "14.2" mph.
    static func speed(_ secondsPerUnit: Double?) -> String {
        guard let s = secondsPerUnit, s.isFinite, s > 0 else { return "-.-" }
        return String(format: "%.1f", 3600 / s)
    }

    static func pace(_ secondsPerUnit: Double?) -> String {
        guard let s = secondsPerUnit, s.isFinite, s > 0 else { return "-:--" }
        let total = Int(s.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "MM:SS" until the first hour, "H:MM:SS" after. `forceHours` always
    /// shows "HH:MM:SS" — the full-screen recorder uses that.
    static func clock(_ seconds: TimeInterval, forceHours: Bool = false) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if forceHours { return String(format: "%02d:%02d:%02d", h, m, s) }
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }

    /// "9 minutes 5 seconds", "1 hour 2 minutes", "45 seconds". Lives here
    /// rather than with the voice cues because Sport needs it and Sport is
    /// compiled into the widget extension.
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        var out: [String] = []
        if h > 0 { out.append("\(h) \(h == 1 ? "hour" : "hours")") }
        if m > 0 { out.append("\(m) \(m == 1 ? "minute" : "minutes")") }
        if s > 0 || out.isEmpty { out.append("\(s) \(s == 1 ? "second" : "seconds")") }
        return out.joined(separator: " ")
    }

    /// "1h 02m", "42m 10s", "58s".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%dh %02dm", h, m) }
        if m > 0 { return String(format: "%dm %02ds", m, s) }
        return "\(s)s"
    }

    static func defaultTitle(for date: Date, sport: Sport = .run, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let part: String
        switch hour {
        case 4..<12: part = "Morning"
        case 12..<17: part = "Afternoon"
        case 17..<21: part = "Evening"
        default: part = "Night"
        }
        return "\(part) \(sport.title)"
    }
}

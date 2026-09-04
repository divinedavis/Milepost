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
}

/// Pace is seconds per unit distance. Anything outside a plausible running
/// range reads as "-:--" instead of a nonsense number from GPS jitter.
enum Pace {
    static let fastestSecondsPerUnit: Double = 2 * 60
    static let slowestSecondsPerUnit: Double = 40 * 60
    static let minimumDistanceMeters: Double = 10

    static func secondsPerUnit(distanceMeters: Double, seconds: TimeInterval, unit: DistanceUnit) -> Double? {
        guard distanceMeters >= minimumDistanceMeters, seconds > 0 else { return nil }
        let pace = seconds / (distanceMeters / unit.meters)
        guard pace >= fastestSecondsPerUnit, pace <= slowestSecondsPerUnit else { return nil }
        return pace
    }
}

enum Format {
    static func distance(_ meters: Double, unit: DistanceUnit) -> String {
        String(format: "%.2f", meters / unit.meters)
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

    static func defaultTitle(for date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 4..<12: return "Morning Run"
        case 12..<17: return "Afternoon Run"
        case 17..<21: return "Evening Run"
        default: return "Night Run"
        }
    }
}

import Foundation
import SwiftUI
import UIKit

/// Holidays Milepost dresses up for (owner, 2026-10-22: "we should also have
/// holiday themes like we do with marracat ... keep the running days").
/// Everything comes from Resources/holidays.json, which the App Store event
/// script reads too, so a day's colours, dates and copy live in one place.
/// Ported from Marracat's HolidayTheme.swift; the date rules are identical.
///
/// On a holiday the launch splash names the day, the Start button and the tab
/// bar's pill fill with its colours, a rim of them turns round the Record
/// panel, and (on by default) the Home Screen icon switches.
struct Holiday: Decodable, Identifiable, Equatable {
    struct DateRule: Decodable, Equatable {
        let month: Int
        let day: Int?
        /// ISO weekday, 1 = Monday ... 7 = Sunday.
        let weekday: Int?
        /// Which one in the month; -1 is the last.
        let nth: Int?
        let offset: Int?
    }

    struct Span: Decodable, Equatable {
        let from: Int
        let to: Int
    }

    let id: String
    let name: String
    let date: DateRule
    /// The days around the date the app wears it; nil for an event-only day.
    let theme: Span?
    /// The launch splash's line ("TURKEY TROT" days say "THANKSGIVING").
    let line: String
    let icon: String
    let tab: [String]

    /// The day in `year`, in the given calendar.
    func day(in year: Int, calendar: Calendar = .holidays) -> Date? {
        let base: Date
        if let d = date.day {
            guard let fixed = calendar.date(from: DateComponents(year: year, month: date.month, day: d)) else { return nil }
            base = fixed
        } else if let weekday = date.weekday, let nth = date.nth, nth != 0 {
            // Counted by hand: the nth from the first of the month, or back
            // from its last day for nth -1 (Memorial Day).
            let want = weekday % 7 + 1   // Calendar's weekday is 1 = Sunday; the JSON's is ISO.
            guard let first = calendar.date(from: DateComponents(year: year, month: date.month, day: 1)),
                  let days = calendar.range(of: .day, in: .month, for: first)?.count else { return nil }
            if nth > 0 {
                let lead = (want - calendar.component(.weekday, from: first) + 7) % 7
                guard let d = calendar.date(byAdding: .day, value: lead + (nth - 1) * 7, to: first) else { return nil }
                base = d
            } else {
                guard let last = calendar.date(byAdding: .day, value: days - 1, to: first) else { return nil }
                let back = (calendar.component(.weekday, from: last) - want + 7) % 7
                guard let d = calendar.date(byAdding: .day, value: -back, to: last) else { return nil }
                base = d
            }
            guard calendar.component(.month, from: base) == date.month else { return nil }
        } else {
            return nil
        }
        return calendar.date(byAdding: .day, value: date.offset ?? 0, to: base)
    }

    /// The days it themes the app in `year`, or nil for an event-only day.
    func themed(in year: Int, calendar: Calendar = .holidays) -> ClosedRange<Date>? {
        guard let theme, let day = day(in: year, calendar: calendar),
              let a = calendar.date(byAdding: .day, value: theme.from, to: day),
              let b = calendar.date(byAdding: .day, value: theme.to, to: day) else { return nil }
        return a...b
    }

    var tabColors: [Color] { tab.map(Color.init(hex:)) }
    /// The first colour, for glows.
    var glow: Color { tabColors.first ?? Theme.accent }
}

enum HolidayCalendar {
    private struct File: Decodable {
        let holidays: [Holiday]
    }

    private static let file: File? = {
        guard let url = Bundle.main.url(forResource: "holidays", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: data)
    }()

    static var holidays: [Holiday] { file?.holidays ?? [] }

    /// `-HOLIDAY <id>` (launch-argument defaults) dresses the app for one day
    /// whatever the date: UI tests, screenshots and previewing a theme.
    /// `-HOLIDAY none` is the everyday app.
    private static var forced: String? { UserDefaults.standard.string(forKey: "HOLIDAY") }

    /// The holiday the app wears on `date`, by the runner's calendar day.
    /// Overlapping themes go to the shortest, so a single day beats the
    /// season around it (Malcolm X Day inside Black History Month's run-up
    /// would win; today none of Milepost's overlap except at the edges).
    /// `list` is for tests; they pass their own and skip the overrides.
    static func current(on date: Date = Date(), calendar: Calendar = .holidays,
                        in list: [Holiday]? = nil) -> Holiday? {
        let list = list ?? holidays
        if list == holidays, let forced { return forced == "none" ? nil : list.first { $0.id == forced } }
        // UI tests see the everyday app unless they name a day: a run on a
        // holiday mustn't change what every other test looks for.
        if list == holidays, ProcessInfo.processInfo.arguments.contains("-uitest") { return nil }
        let day = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: day)
        var best: (Holiday, Int)?
        for h in list {
            for y in [year - 1, year, year + 1] {
                guard let range = h.themed(in: y, calendar: calendar), range.contains(day) else { continue }
                let length = calendar.dateComponents([.day], from: range.lowerBound, to: range.upperBound).day ?? 0
                if best == nil || length < best!.1 { best = (h, length) }
            }
        }
        return best?.0
    }
}

/// The holiday the app is wearing right now, refreshed when it comes back to
/// the front (a theme can start overnight while it sits in the background).
@MainActor
@Observable
final class HolidayStore {
    private(set) var current: Holiday? = HolidayCalendar.current()

    func refresh() {
        let now = HolidayCalendar.current()
        if now != current { current = now }
        HolidayIcon.apply()
    }
}

extension Calendar {
    /// Gregorian in the device's time zone: a holiday starts at the runner's
    /// midnight, wherever they are.
    static var holidays: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }
}

extension Color {
    /// "#RRGGBB".
    init(hex: String) {
        let v = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

/// The Home Screen icon. On by default, like Marracat's (owner, 2026-10-20:
/// "auto on by default and the users can turn it off in their settings");
/// iOS shows its own "You have changed the icon" alert on each switch, which
/// no app can hide. Profile > Settings > "Holiday app icons" turns it off.
enum HolidayIcon {
    static let settingKey = "holidayIcons"
    static let enabledDefault = true

    static var enabled: Bool { UserDefaults.standard.object(forKey: settingKey) as? Bool ?? enabledDefault }

    /// The icon this day should have: the holiday's while one is on and the
    /// setting is, the everyday one otherwise.
    static func wanted(on date: Date = Date()) -> String? {
        guard enabled, let h = HolidayCalendar.current(on: date) else { return nil }
        return h.icon
    }

    /// Switch to the wanted icon if it isn't already showing. Only while the
    /// app is active: iOS refuses the change from the background.
    @MainActor
    static func apply() {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.applicationState == .active else { return }
        // UI tests never get the system's icon alert over what they check.
        guard !ProcessInfo.processInfo.arguments.contains("-uitest") else { return }
        let want = wanted()
        guard app.alternateIconName != want else { return }
        app.setAlternateIconName(want) { _ in }
    }
}

import XCTest
@testable import Milepost

/// Holiday themes (2026-10-22). The date rules are Marracat's, checked here
/// against Milepost's own list and real calendars.
final class HolidayTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func holiday(_ id: String) throws -> Holiday {
        try XCTUnwrap(HolidayCalendar.holidays.first { $0.id == id }, "\(id) missing from holidays.json")
    }

    func testTheBundledListLoadsWithTheRunningDays() {
        let ids = HolidayCalendar.holidays.map(\.id)
        XCTAssertEqual(ids.count, 23, "Marracat's 21 days plus the two running days")
        XCTAssertEqual(Set(ids).count, ids.count, "ids must be unique")
        XCTAssertTrue(ids.contains("global-running-day"))
        XCTAssertTrue(ids.contains("nyc-marathon"))
        XCTAssertTrue(ids.contains("black-friday"), "same days as Marracat (owner, 2026-10-22)")
        XCTAssertTrue(ids.contains("gift-guide"))
        for h in HolidayCalendar.holidays {
            XCTAssertEqual(h.icon, "AppIcon-\(h.id)")
            XCTAssertFalse(h.tab.isEmpty, h.id)
            XCTAssertNotNil(h.theme, h.id)
        }
    }

    func testDatesLandOnTheRightDays() throws {
        let cases: [(String, Int, Int, Int)] = [
            ("thanksgiving", 2026, 11, 26),      // fourth Thursday
            ("nyc-marathon", 2026, 11, 1),       // first Sunday
            ("mlk", 2027, 1, 18),                // third Monday
            ("presidents", 2027, 2, 15),
            ("memorial", 2027, 5, 31),           // last Monday
            ("global-running-day", 2027, 6, 2),  // first Wednesday
            ("labor", 2027, 9, 6),
            ("indigenous", 2026, 10, 12),
            ("juneteenth", 2027, 6, 19),
        ]
        for (id, y, m, d) in cases {
            let day = try holiday(id).day(in: y, calendar: calendar)
            XCTAssertEqual(day, calendar.date(from: DateComponents(year: y, month: m, day: d)), id)
        }
    }

    /// Marracat's windows: the holiday season (Nov 20 - Dec 18) around the
    /// single days, each single day winning on its own date.
    func testThanksgivingWeekMatchesMarracat() throws {
        let list = HolidayCalendar.holidays
        XCTAssertEqual(HolidayCalendar.current(on: date(2026, 11, 24), calendar: calendar, in: list)?.id, "gift-guide")
        XCTAssertEqual(HolidayCalendar.current(on: date(2026, 11, 26, hour: 23), calendar: calendar, in: list)?.id, "thanksgiving")
        XCTAssertEqual(HolidayCalendar.current(on: date(2026, 11, 27), calendar: calendar, in: list)?.id, "black-friday")
        XCTAssertEqual(HolidayCalendar.current(on: date(2026, 11, 30), calendar: calendar, in: list)?.id, "cyber-monday")
        XCTAssertNil(HolidayCalendar.current(on: date(2026, 8, 12), calendar: calendar, in: list), "an ordinary day")
    }

    /// Every Marracat day has Marracat's dates and windows.
    func testDaysAndWindowsMatchMarracat() throws {
        let cases: [(String, Int, Int, Int)] = [
            ("black-friday", 2026, 11, 27), ("cyber-monday", 2026, 11, 30), ("gift-guide", 2026, 11, 20),
        ]
        for (id, y, m, d) in cases {
            XCTAssertEqual(try holiday(id).day(in: y, calendar: calendar),
                           calendar.date(from: DateComponents(year: y, month: m, day: d)), id)
        }
    }

    func testMarathonSundayFollowsHalloween() {
        let list = HolidayCalendar.holidays
        XCTAssertEqual(HolidayCalendar.current(on: date(2026, 10, 31), calendar: calendar, in: list)?.id, "halloween")
        XCTAssertEqual(HolidayCalendar.current(on: date(2026, 11, 1), calendar: calendar, in: list)?.id, "nyc-marathon")
    }

    func testTheShortestOverlappingThemeWins() {
        let long = Holiday(id: "season", name: "Season", date: .init(month: 12, day: 20, weekday: nil, nth: nil, offset: nil),
                           theme: .init(from: -20, to: 0), line: "", icon: "", tab: ["#000000"])
        let short = Holiday(id: "day", name: "Day", date: .init(month: 12, day: 10, weekday: nil, nth: nil, offset: nil),
                            theme: .init(from: 0, to: 0), line: "", icon: "", tab: ["#FFFFFF"])
        XCTAssertEqual(HolidayCalendar.current(on: date(2026, 12, 10), calendar: calendar, in: [long, short])?.id, "day")
        XCTAssertEqual(HolidayCalendar.current(on: date(2026, 12, 11), calendar: calendar, in: [long, short])?.id, "season")
    }

    func testAThemeCrossingNewYearIsFound() throws {
        // Kwanzaa runs Dec 26 - Jan 1: a January date must look back a year.
        let kwanzaa = try holiday("kwanzaa")
        guard let range = kwanzaa.themed(in: 2026, calendar: calendar) else { return XCTFail("no range") }
        XCTAssertTrue(range.contains(calendar.startOfDay(for: date(2026, 12, 27))))
    }

    func testHolidayIconsAreOnByDefault() {
        XCTAssertTrue(HolidayIcon.enabledDefault)
    }
}

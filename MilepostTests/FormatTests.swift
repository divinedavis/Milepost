import XCTest
@testable import Milepost

final class FormatTests: XCTestCase {

    func testPaceFormatting() {
        XCTAssertEqual(Format.pace(nil), "-:--")
        XCTAssertEqual(Format.pace(0), "-:--")
        XCTAssertEqual(Format.pace(512), "8:32")
        XCTAssertEqual(Format.pace(605.4), "10:05")
    }

    func testPaceRejectsImplausibleValues() {
        XCTAssertNil(Pace.secondsPerUnit(distanceMeters: 5, seconds: 60, unit: .miles), "too short to judge")
        XCTAssertNil(Pace.secondsPerUnit(distanceMeters: 1609.344, seconds: 30, unit: .miles), "30-second mile")
        XCTAssertNil(Pace.secondsPerUnit(distanceMeters: 100, seconds: 3600, unit: .miles), "slower than a crawl")
        XCTAssertEqual(Pace.secondsPerUnit(distanceMeters: 1609.344, seconds: 480, unit: .miles)!, 480, accuracy: 0.01)
        XCTAssertEqual(Pace.secondsPerUnit(distanceMeters: 1000, seconds: 300, unit: .kilometers)!, 300, accuracy: 0.01)
    }

    func testClock() {
        XCTAssertEqual(Format.clock(0), "00:00")
        XCTAssertEqual(Format.clock(0, forceHours: true), "00:00:00")
        XCTAssertEqual(Format.clock(65), "01:05")
        XCTAssertEqual(Format.clock(3725), "1:02:05")
        XCTAssertEqual(Format.clock(3725, forceHours: true), "01:02:05")
    }

    func testDuration() {
        XCTAssertEqual(Format.duration(58), "58s")
        XCTAssertEqual(Format.duration(130), "2m 10s")
        XCTAssertEqual(Format.duration(3720), "1h 02m")
    }

    func testDistance() {
        XCTAssertEqual(Format.distance(1609.344, unit: .miles), "1.00")
        XCTAssertEqual(Format.distance(2500, unit: .kilometers), "2.50")
        XCTAssertEqual(Format.distance(0, unit: .miles), "0.00")
    }

    func testDefaultTitleFollowsTimeOfDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        func at(_ hour: Int) -> Date {
            cal.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: hour))!
        }
        XCTAssertEqual(Format.defaultTitle(for: at(7), calendar: cal), "Morning Run")
        XCTAssertEqual(Format.defaultTitle(for: at(13), calendar: cal), "Afternoon Run")
        XCTAssertEqual(Format.defaultTitle(for: at(18), calendar: cal), "Evening Run")
        XCTAssertEqual(Format.defaultTitle(for: at(23), calendar: cal), "Night Run")
    }
}

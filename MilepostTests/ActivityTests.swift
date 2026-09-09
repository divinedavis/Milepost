import CoreLocation
import MapKit
import SwiftData
import XCTest
@testable import Milepost

@MainActor
final class ActivityTests: XCTestCase {

    private func summary(start: Date, meters: Double, seconds: TimeInterval, sport: Sport = .run) -> RunSummary {
        let route = [
            RoutePoint(latitude: 40.68, longitude: -73.97, timestamp: start),
            RoutePoint(latitude: 40.69, longitude: -73.97, timestamp: start.addingTimeInterval(seconds)),
        ]
        return RunSummary(startDate: start, endDate: start.addingTimeInterval(seconds + 30),
                          movingSeconds: seconds, distanceMeters: meters,
                          splitMeters: DistanceUnit.miles.meters, route: route,
                          splits: [Split(index: 1, distanceMeters: meters, seconds: seconds)],
                          sport: sport)
    }

    func testRouteAndSplitsRoundTripThroughTheStore() throws {
        let container = try ModelContainer(for: Activity.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let a = Activity(summary: summary(start: start, meters: 1200, seconds: 420), title: "Test")
        context.insert(a)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Activity>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].route.count, 2)
        XCTAssertEqual(fetched[0].route[1].latitude, 40.69, accuracy: 0.0001)
        XCTAssertEqual(fetched[0].splits.first?.seconds, 420)
        XCTAssertEqual(fetched[0].recordedUnit, .miles)
        XCTAssertEqual(fetched[0].averagePace(unit: .miles)!, 420 / (1200 / 1609.344), accuracy: 0.01)
    }

    func testWeeklyTotalsOnlyCountThisWeek() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let now = cal.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 9))!
        let thisWeek = cal.date(from: DateComponents(year: 2026, month: 9, day: 2, hour: 7))!
        let lastWeek = cal.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 7))!

        let a = Activity(summary: summary(start: thisWeek, meters: 3000, seconds: 900), title: "a")
        let b = Activity(summary: summary(start: lastWeek, meters: 5000, seconds: 1500), title: "b")

        let week = ActivityStats.thisWeek([a, b], now: now, calendar: cal)
        XCTAssertEqual(week.count, 1)
        XCTAssertEqual(week.distanceMeters, 3000)
        XCTAssertEqual(week.seconds, 900)

        let all = ActivityStats.totals([a, b])
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.distanceMeters, 8000)
        XCTAssertEqual(all.averagePace(unit: .kilometers)!, 300, accuracy: 0.01)
    }

    func testFittedRectCoversEveryPoint() {
        let coords = [
            CLLocationCoordinate2D(latitude: 40.68, longitude: -73.97),
            CLLocationCoordinate2D(latitude: 40.70, longitude: -73.95),
        ]
        let rect = RouteGeometry.fittedRect(coords)!
        for c in coords {
            XCTAssertTrue(rect.contains(MKMapPoint(c)))
        }
        XCTAssertNil(RouteGeometry.fittedRect([]))
    }
}

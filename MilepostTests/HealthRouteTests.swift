import CoreLocation
import HealthKit
import XCTest
@testable import Milepost

/// Other apps' Apple Health workouts on "Your map" (2026-10-23): off until
/// asked, only walks/runs/rides, and never a second line for an outing
/// Milepost already has.
@MainActor
final class HealthRouteTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)
    private let path = [CLLocationCoordinate2D(latitude: 40.68, longitude: -73.97),
                        CLLocationCoordinate2D(latitude: 40.69, longitude: -73.96)]

    private func route(start: Date? = nil, externalID: String? = nil, brand: String? = nil) -> HealthRoute {
        HealthRoute(id: UUID(), sport: .run, start: start ?? self.start,
                    externalID: externalID, brand: brand, coordinates: path)
    }

    private func activity(start: Date) -> Activity {
        Activity(title: "Run", startDate: start, endDate: start.addingTimeInterval(1_800),
                 movingSeconds: 1_800, distanceMeters: 5_000, splitMeters: 1_609.344,
                 route: path.enumerated().map { RoutePoint(latitude: $1.latitude, longitude: $1.longitude,
                                                          timestamp: start.addingTimeInterval(Double($0))) },
                 splits: [])
    }

    func testOffByDefault() {
        XCTAssertFalse(HealthSettings.mapDefault)
    }

    func testOnlyWalksRunsAndRidesAreDrawn() {
        XCTAssertEqual(HealthRouteRules.sport(for: .running), .run)
        XCTAssertEqual(HealthRouteRules.sport(for: .walking), .walk)
        XCTAssertEqual(HealthRouteRules.sport(for: .hiking), .walk)
        XCTAssertEqual(HealthRouteRules.sport(for: .cycling), .bike)
        XCTAssertNil(HealthRouteRules.sport(for: .swimming))
        XCTAssertNil(HealthRouteRules.sport(for: .yoga))
    }

    func testMilepostsOwnWorkoutsAreNotDrawnTwice() {
        let mine = activity(start: start.addingTimeInterval(-86_400))
        XCTAssertTrue(HealthRouteRules.isAlreadyOnMap(route(brand: "Milepost"), activities: []))
        XCTAssertTrue(HealthRouteRules.isAlreadyOnMap(route(externalID: mine.id.uuidString), activities: [mine]))

        let saved = route(start: start.addingTimeInterval(-86_400 * 3))
        mine.healthWorkoutID = saved.id.uuidString
        XCTAssertTrue(HealthRouteRules.isAlreadyOnMap(saved, activities: [mine]))
    }

    func testAWatchWorkoutAlongsideAMilepostRunIsTheSameOuting() {
        let mine = activity(start: start)
        XCTAssertTrue(HealthRouteRules.isAlreadyOnMap(route(start: start.addingTimeInterval(90)), activities: [mine]))
        XCTAssertFalse(HealthRouteRules.isAlreadyOnMap(route(start: start.addingTimeInterval(600)), activities: [mine]))
    }

    func testTheMapHasBothAndMarksHealthLines() {
        let mine = activity(start: start)
        let lines = RouteLine.all(activities: [mine],
                                  health: [route(start: start.addingTimeInterval(30)),
                                           route(start: start.addingTimeInterval(86_400))])
        XCTAssertEqual(lines.count, 2, "the one alongside Milepost's run is dropped")
        XCTAssertEqual(lines.filter(\.fromHealth).count, 1)
    }
}

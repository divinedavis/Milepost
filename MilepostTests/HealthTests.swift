import CoreLocation
import HealthKit
import SwiftData
import XCTest
@testable import Milepost

/// Everything about the Health layer that can be checked without a Health
/// database: the arithmetic, the shapes, and the privacy rule that decides
/// whether a route ever leaves the phone.
@MainActor
final class HealthTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: Calories

    func testRunningBurnsMoreThanWalkingAtTheSameSpeed() {
        let meters = 3000.0, seconds = 900.0
        let run = CalorieEstimator.activeKilocalories(sport: .run, distanceMeters: meters, movingSeconds: seconds)
        let walk = CalorieEstimator.activeKilocalories(sport: .walk, distanceMeters: meters, movingSeconds: seconds)
        XCTAssertNotNil(run)
        XCTAssertNotNil(walk)
        XCTAssertGreaterThan(run!, walk!)
    }

    func testCaloriesScaleWithBodyMass() {
        let light = CalorieEstimator.activeKilocalories(sport: .run, distanceMeters: 5000, movingSeconds: 1500, bodyMassKilograms: 60)
        let heavy = CalorieEstimator.activeKilocalories(sport: .run, distanceMeters: 5000, movingSeconds: 1500, bodyMassKilograms: 90)
        XCTAssertNotNil(light)
        XCTAssertNotNil(heavy)
        // Linear in mass: 90 kg burns exactly half again what 60 kg does.
        XCTAssertEqual(heavy! / light!, 1.5, accuracy: 0.001)
    }

    /// A 70 kg runner at a 9:00 mile for 30 minutes is a little over 400 kcal
    /// by every published table. A model that drifts far from that is wrong in
    /// a way nobody would notice from the code alone.
    func testRunEstimateLandsInTheRightBallpark() {
        let meters = 1609.344 * 30.0 / 9.0     // 30 minutes at 9:00/mi
        let kcal = CalorieEstimator.activeKilocalories(sport: .run, distanceMeters: meters, movingSeconds: 1800, bodyMassKilograms: 70)
        XCTAssertNotNil(kcal)
        XCTAssertGreaterThan(kcal!, 300)
        XCTAssertLessThan(kcal!, 500)
    }

    func testImplausibleSpeedProducesNoEstimate() {
        // 100 m in 1 second is GPS noise, not a sprint. A number here would be
        // worse than nothing: it would go into Health as real.
        XCTAssertNil(CalorieEstimator.activeKilocalories(sport: .run, distanceMeters: 100, movingSeconds: 1))
        XCTAssertNil(CalorieEstimator.activeKilocalories(sport: .run, distanceMeters: 0, movingSeconds: 600))
        XCTAssertNil(CalorieEstimator.activeKilocalories(sport: .run, distanceMeters: 1000, movingSeconds: 0))
    }

    func testCyclingMETsClimbWithSpeed() {
        let slow = CalorieEstimator.metabolicEquivalent(sport: .bike, metersPerSecond: 4)    // ~14 km/h
        let fast = CalorieEstimator.metabolicEquivalent(sport: .bike, metersPerSecond: 8)    // ~29 km/h
        XCTAssertGreaterThan(fast, slow)
    }

    // MARK: Heart rate source

    func testHeartRateSourceNamesOuraAlone() {
        XCTAssertEqual(HealthMetrics.sourceLabel(["Oura", "Oura"]), "Oura")
    }

    func testHeartRateSourceListsRingAndWatchInAStableOrder() {
        let label = HealthMetrics.sourceLabel(["Oura", "Jo's Apple Watch"])
        XCTAssertEqual(label, HealthMetrics.sourceLabel(["Jo's Apple Watch", "Oura"]))
        XCTAssertEqual(label, "Jo's Apple Watch and Oura")
    }

    func testNoSourceMeansNoLabel() {
        XCTAssertNil(HealthMetrics.sourceLabel([]))
        XCTAssertNil(HealthMetrics.sourceLabel([""]))
    }

    // MARK: Split timeline

    private func route(from start: Date, meters: Double, seconds: TimeInterval, step: Double = 50) -> [RoutePoint] {
        var points: [RoutePoint] = []
        var covered = 0.0
        while covered <= meters {
            let fraction = covered / max(meters, 1)
            points.append(RoutePoint(latitude: 40.68 + fraction * 0.01,
                                     longitude: -73.97,
                                     timestamp: start.addingTimeInterval(seconds * fraction),
                                     altitude: 10,
                                     horizontalAccuracy: 5,
                                     verticalAccuracy: 3,
                                     speed: meters / seconds,
                                     cumulativeMeters: covered))
            covered += step
        }
        return points
    }

    func testSplitRangesLandOnTheRealCrossingTimes() {
        let mile = DistanceUnit.miles.meters
        let seconds = 1200.0                       // 2 miles in 20 minutes
        let points = route(from: start, meters: mile * 2, seconds: seconds)
        let splits = [Split(index: 1, distanceMeters: mile, seconds: 600),
                      Split(index: 2, distanceMeters: mile, seconds: 600)]

        let ranges = SplitTimeline.ranges(splits: splits, splitMeters: mile, route: points,
                                          startDate: start, endDate: start.addingTimeInterval(seconds))
        XCTAssertEqual(ranges.count, 2)
        // Each range knows which split it belongs to, so a dropped one cannot
        // silently shift the rest onto the wrong split.
        XCTAssertEqual(ranges.map(\.split.index), [1, 2])
        // The first mile ends halfway through an evenly paced two-mile run.
        XCTAssertEqual(ranges[0].end.timeIntervalSince(start), 600, accuracy: 15)
        XCTAssertEqual(ranges[1].start, ranges[0].end)
        // Segments must not overlap or HealthKit rejects them.
        XCTAssertLessThan(ranges[0].start, ranges[0].end)
        XCTAssertLessThan(ranges[1].start, ranges[1].end)
    }

    /// A route stored before cumulative distance existed cannot say when a
    /// split was crossed, and the timeline must say so rather than inventing
    /// evenly spaced laps.
    func testLegacyRouteWithoutCumulativeDistanceYieldsNoRanges() {
        let points = [RoutePoint(latitude: 40.68, longitude: -73.97, timestamp: start),
                      RoutePoint(latitude: 40.69, longitude: -73.97, timestamp: start.addingTimeInterval(600))]
        let ranges = SplitTimeline.ranges(splits: [Split(index: 1, distanceMeters: 1609, seconds: 600)],
                                          splitMeters: DistanceUnit.miles.meters,
                                          route: points, startDate: start,
                                          endDate: start.addingTimeInterval(600))
        XCTAssertTrue(ranges.isEmpty)
    }

    func testElevationIgnoresBarometerNoise() {
        // Standing still with the altimeter wandering by half a meter.
        let jitter = (0..<60).map { i in
            RoutePoint(latitude: 40.68, longitude: -73.97,
                       timestamp: start.addingTimeInterval(Double(i)),
                       altitude: 10 + (i % 2 == 0 ? 0.4 : -0.4),
                       horizontalAccuracy: 5, verticalAccuracy: 3)
        }
        XCTAssertEqual(SplitTimeline.elevationAscended(route: jitter) ?? -1, 0, accuracy: 0.001)

        let climb = (0..<10).map { i in
            RoutePoint(latitude: 40.68, longitude: -73.97,
                       timestamp: start.addingTimeInterval(Double(i) * 10),
                       altitude: 10 + Double(i) * 5,
                       horizontalAccuracy: 5, verticalAccuracy: 3)
        }
        XCTAssertEqual(SplitTimeline.elevationAscended(route: climb) ?? 0, 45, accuracy: 0.001)
        XCTAssertEqual(SplitTimeline.elevationDescended(route: climb) ?? -1, 0, accuracy: 0.001)
    }

    func testElevationNeedsAValidVerticalAccuracy() {
        // A fix with no altitude reading reports -1 vertical accuracy; counting
        // its altitude of 0 would read as a cliff.
        let points = [RoutePoint(latitude: 40.68, longitude: -73.97, timestamp: start,
                                 altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1),
                      RoutePoint(latitude: 40.68, longitude: -73.97, timestamp: start.addingTimeInterval(10),
                                 altitude: 0, horizontalAccuracy: 5, verticalAccuracy: -1)]
        XCTAssertNil(SplitTimeline.elevationAscended(route: points))
    }

    // MARK: Route points

    func testLegacyRoutePointStillMakesAUsableLocation() {
        let point = RoutePoint(latitude: 40.68, longitude: -73.97, timestamp: start)
        let location = point.location
        // HealthKit drops a route point whose horizontal accuracy is not
        // positive, so the fallback has to be a real number.
        XCTAssertGreaterThan(location.horizontalAccuracy, 0)
        XCTAssertEqual(location.horizontalAccuracy, RunRecorder.maxHorizontalAccuracy)
        // No altitude was recorded, and the location must not claim one.
        XCTAssertLessThan(location.verticalAccuracy, 0)
    }

    func testRoutePointDecodesFromAPreHealthEncoding() throws {
        // Exactly what 1.0 wrote: three keys, nothing else.
        let json = #"{"latitude":40.68,"longitude":-73.97,"timestamp":757400000}"#
        let point = try JSONDecoder().decode(RoutePoint.self, from: Data(json.utf8))
        XCTAssertEqual(point.latitude, 40.68, accuracy: 0.0001)
        XCTAssertNil(point.altitude)
        XCTAssertNil(point.cumulativeMeters)
    }

    // MARK: Settings

    /// The promise the app makes on the You tab and in the App Store listing.
    /// If either default flips, routes start leaving the phone for people who
    /// never asked for that.
    func testHealthAndRouteWritingAreBothOffByDefault() {
        XCTAssertFalse(HealthSettings.enabledDefault)
        XCTAssertFalse(HealthSettings.routeDefault)
    }

    // MARK: Sport mapping

    func testSportsMapToTheRightHealthTypes() {
        XCTAssertEqual(Sport.run.workoutActivityType, .running)
        XCTAssertEqual(Sport.strollerRun.workoutActivityType, .running)
        XCTAssertEqual(Sport.walk.workoutActivityType, .walking)
        XCTAssertEqual(Sport.bike.workoutActivityType, .cycling)

        XCTAssertEqual(Sport.bike.distanceQuantityType, HKQuantityType(.distanceCycling))
        XCTAssertEqual(Sport.run.distanceQuantityType, HKQuantityType(.distanceWalkingRunning))
        XCTAssertEqual(Sport.walk.distanceQuantityType, HKQuantityType(.distanceWalkingRunning))
    }

    /// Health has no stroller running. Filing it as a plain run is right, but
    /// the distinction has to survive somewhere or it is simply lost.
    func testStrollerRunKeepsItsIdentityInMetadata() {
        XCTAssertFalse(Sport.strollerRun.healthBrandMetadata.isEmpty)
        XCTAssertTrue(Sport.run.healthBrandMetadata.isEmpty)
    }
}

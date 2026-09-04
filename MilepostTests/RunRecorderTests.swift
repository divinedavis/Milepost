import CoreLocation
import XCTest
@testable import Milepost

@MainActor
final class RunRecorderTests: XCTestCase {

    private var clock = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeRecorder() -> RunRecorder {
        RunRecorder(now: { [unowned self] in self.clock })
    }

    private static let baseLatitude = 40.68

    /// Metres per degree of latitude at the base, measured the way the engine
    /// measures (WGS-84 via CLLocation), so fixtures land exactly.
    private static let metersPerDegree: Double = {
        let a = CLLocation(latitude: baseLatitude, longitude: -73.97)
        let b = CLLocation(latitude: baseLatitude + 0.01, longitude: -73.97)
        return b.distance(from: a) * 100
    }()

    /// Points spaced along a meridian: `metersNorth` metres north of a base.
    private func fix(_ metersNorth: Double, at seconds: TimeInterval, accuracy: CLLocationAccuracy = 5, speed: CLLocationSpeed = -1) -> CLLocation {
        let lat = Self.baseLatitude + metersNorth / Self.metersPerDegree
        return CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: -73.97),
                          altitude: 10, horizontalAccuracy: accuracy, verticalAccuracy: 5,
                          course: 0, speed: speed,
                          timestamp: Date(timeIntervalSince1970: 1_700_000_000 + seconds))
    }

    func testStartResetsAndBeginsRecording() {
        let r = makeRecorder()
        XCTAssertEqual(r.state, .idle)
        r.start(unit: .miles)
        XCTAssertEqual(r.state, .recording)
        XCTAssertEqual(r.distanceMeters, 0)
        XCTAssertEqual(r.splits.count, 1)
        XCTAssertFalse(r.hasMovement)
    }

    func testDistanceAccumulatesBetweenAcceptedFixes() {
        let r = makeRecorder()
        r.start(unit: .miles)
        r.ingest(fix(0, at: 1))
        r.ingest(fix(100, at: 31))
        r.ingest(fix(200, at: 61))
        XCTAssertEqual(r.distanceMeters, 200, accuracy: 1)
        XCTAssertEqual(r.route.count, 3)
        XCTAssertTrue(r.hasMovement)
    }

    func testPoorAccuracyAndStaleFixesAreDropped() {
        let r = makeRecorder()
        r.start(unit: .miles)
        r.ingest(fix(0, at: 1))
        r.ingest(fix(100, at: 5, accuracy: 60))        // too imprecise
        r.ingest(fix(300, at: -30))                    // before the run began
        XCTAssertEqual(r.distanceMeters, 0)
        XCTAssertEqual(r.route.count, 1)
    }

    func testStationarySpeedCountsNothing() {
        let r = makeRecorder()
        r.start(unit: .miles)
        r.ingest(fix(0, at: 1))
        r.ingest(fix(8, at: 2, speed: 0))              // drift while standing
        r.ingest(fix(16, at: 3, speed: 0.1))
        XCTAssertEqual(r.distanceMeters, 0)
        // Then a real move is measured from the last drift anchor, not from zero.
        r.ingest(fix(26, at: 4, speed: 3))
        XCTAssertEqual(r.distanceMeters, 10, accuracy: 0.5)
    }

    func testTinyStepsAreIgnored() {
        let r = makeRecorder()
        r.start(unit: .miles)
        r.ingest(fix(0, at: 1))
        r.ingest(fix(0.4, at: 2))
        XCTAssertEqual(r.distanceMeters, 0)
    }

    func testPauseIgnoresFixesAndDropsTheAnchor() {
        let r = makeRecorder()
        r.start(unit: .miles)
        r.ingest(fix(0, at: 1))
        r.ingest(fix(50, at: 11))
        clock = clock.addingTimeInterval(11)
        r.pause()
        XCTAssertEqual(r.state, .paused)
        r.ingest(fix(500, at: 20))                     // walked off while paused
        XCTAssertEqual(r.distanceMeters, 50, accuracy: 1)
        clock = clock.addingTimeInterval(20)
        r.resume()
        r.ingest(fix(500, at: 32))                     // first fix after resume: anchor only
        XCTAssertEqual(r.distanceMeters, 50, accuracy: 1)
        r.ingest(fix(550, at: 42))
        XCTAssertEqual(r.distanceMeters, 100, accuracy: 1)
    }

    func testElapsedExcludesPausedTime() {
        let r = makeRecorder()
        r.start(unit: .miles)
        clock = clock.addingTimeInterval(60)
        r.refreshElapsed()
        XCTAssertEqual(r.elapsed, 60, accuracy: 0.01)
        r.pause()
        clock = clock.addingTimeInterval(120)
        r.refreshElapsed()
        XCTAssertEqual(r.elapsed, 60, accuracy: 0.01)
        r.resume()
        clock = clock.addingTimeInterval(30)
        r.refreshElapsed()
        XCTAssertEqual(r.elapsed, 90, accuracy: 0.01)
    }

    func testSplitsRollOverAtTheUnitBoundary() {
        let r = makeRecorder()
        r.start(unit: .kilometers)
        r.ingest(fix(0, at: 0))
        r.ingest(fix(600, at: 180))                    // 3:00 per 600 m
        r.ingest(fix(1200, at: 360))                   // crosses 1 km at 300 s
        XCTAssertEqual(r.splits.count, 2)
        let first = r.splits[0]
        XCTAssertTrue(first.isComplete(splitMeters: 1000))
        XCTAssertEqual(first.distanceMeters, 1000, accuracy: 0.01)
        XCTAssertEqual(first.seconds, 300, accuracy: 1)
        let second = r.splits[1]
        XCTAssertEqual(second.index, 2)
        XCTAssertEqual(second.distanceMeters, 200, accuracy: 1)
        XCTAssertEqual(second.seconds, 60, accuracy: 1)
        XCTAssertEqual(second.pace(unit: .kilometers)!, 300, accuracy: 2)
    }

    func testOneHugeStepSpansSeveralSplits() {
        let r = makeRecorder()
        r.start(unit: .kilometers)
        r.ingest(fix(0, at: 0))
        r.ingest(fix(2500, at: 750))
        XCTAssertEqual(r.splits.count, 3)
        XCTAssertEqual(r.splits[0].seconds, 300, accuracy: 0.5)
        XCTAssertEqual(r.splits[1].seconds, 300, accuracy: 0.5)
        XCTAssertEqual(r.splits[2].distanceMeters, 500, accuracy: 0.5)
        XCTAssertEqual(r.splits[2].seconds, 150, accuracy: 0.5)
    }

    func testFinishWithoutMovementReturnsNilAndStaysPaused() {
        let r = makeRecorder()
        r.start(unit: .miles)
        r.ingest(fix(0, at: 1))
        r.ingest(fix(5, at: 5))
        XCTAssertNil(r.finish())
        XCTAssertEqual(r.state, .paused, "Finish must leave the run resumable")
        r.resume()
        XCTAssertEqual(r.state, .recording)
        r.discard()
        XCTAssertEqual(r.state, .idle)
        XCTAssertEqual(r.distanceMeters, 0)
    }

    func testFinishWithMovementReturnsSummary() {
        let r = makeRecorder()
        r.start(unit: .miles)
        r.ingest(fix(0, at: 1))
        r.ingest(fix(400, at: 121))
        clock = clock.addingTimeInterval(121)
        let summary = r.finish()
        XCTAssertNotNil(summary)
        XCTAssertEqual(summary!.distanceMeters, 400, accuracy: 1)
        XCTAssertEqual(summary!.movingSeconds, 121, accuracy: 0.01)
        XCTAssertEqual(summary!.route.count, 2)
        XCTAssertEqual(summary!.splitMeters, DistanceUnit.miles.meters)
        XCTAssertEqual(r.state, .paused)
    }

    func testStartWhileActiveIsIgnored() {
        let r = makeRecorder()
        r.start(unit: .miles)
        r.ingest(fix(0, at: 1))
        r.ingest(fix(100, at: 30))
        r.start(unit: .kilometers)
        XCTAssertEqual(r.unit, .miles)
        XCTAssertEqual(r.distanceMeters, 100, accuracy: 1)
    }
}

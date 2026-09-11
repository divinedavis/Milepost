import CoreLocation
import XCTest
@testable import Milepost

/// The recorder → Live Activity mapping. Everything the Dynamic Island shows
/// comes through `RunActivityController.state(for:)`, so this is where a
/// wrong mile number would surface.
@MainActor
final class RunActivityTests: XCTestCase {

    private var clock = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeRecorder() -> RunRecorder {
        RunRecorder(now: { [unowned self] in self.clock })
    }

    private static let baseLatitude = 40.68
    private static let metersPerDegree: Double = {
        let a = CLLocation(latitude: baseLatitude, longitude: -73.97)
        let b = CLLocation(latitude: baseLatitude + 0.01, longitude: -73.97)
        return b.distance(from: a) * 100
    }()

    private func fix(_ metersNorth: Double, at seconds: TimeInterval) -> CLLocation {
        let lat = Self.baseLatitude + metersNorth / Self.metersPerDegree
        return CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: -73.97),
                          altitude: 10, horizontalAccuracy: 5, verticalAccuracy: 5,
                          course: 0, speed: -1,
                          timestamp: Date(timeIntervalSince1970: 1_700_000_000 + seconds))
    }

    func testFreshRunIsMileOneAtTheStartOfTheTrack() {
        let r = makeRecorder()
        r.start(unit: .miles)
        let s = RunActivityController.state(for: r)
        XCTAssertEqual(s.splitIndex, 1)
        XCTAssertEqual(s.splitFraction, 0)
        XCTAssertEqual(s.distanceUnits, 0)
        XCTAssertNil(s.splitPace)
        XCTAssertFalse(s.isPaused)
        XCTAssertEqual(s.clock, .running(since: clock))
        XCTAssertEqual(s.distanceText(unit: .miles), "0.00 mi")
        XCTAssertEqual(s.detailText(unit: .miles), "Mile 1")
    }

    func testHalfwayThroughTheFirstMile() {
        let r = makeRecorder()
        r.start(unit: .miles)
        r.ingest(fix(0, at: 1))
        clock = clock.addingTimeInterval(300)
        r.ingest(fix(804.672, at: 301))   // exactly half a mile at 10:00/mi
        let s = RunActivityController.state(for: r)
        XCTAssertEqual(s.splitIndex, 1)
        XCTAssertEqual(s.splitFraction, 0.5, accuracy: 0.011)
        XCTAssertEqual(s.distanceUnits, 0.5, accuracy: 0.011)
        XCTAssertEqual(s.splitPace ?? 0, 600, accuracy: 2)
        XCTAssertEqual(s.distanceText(unit: .miles), "0.50 mi")
        XCTAssertEqual(s.detailText(unit: .miles), "Mile 1 · 10:00 /mi")
    }

    /// The right end of the progress line, where Now Playing shows time left.
    func testProgressLineShowsDistanceToTheNextMilepost() {
        let r = makeRecorder()
        r.start(unit: .miles)
        let fresh = RunActivityController.state(for: r)
        XCTAssertEqual(fresh.remainingText(unit: .miles), "−1.00 mi")
        XCTAssertEqual(fresh.remainingDescription(unit: .miles), "1.00 mi to Mile 2")

        r.ingest(fix(0, at: 1))
        clock = clock.addingTimeInterval(300)
        r.ingest(fix(804.672, at: 301))   // half a mile
        let half = RunActivityController.state(for: r)
        XCTAssertEqual(half.remainingText(unit: .miles), "−0.50 mi")
        XCTAssertTrue(RunActivityController.state(for: r).remainingText(unit: .kilometers).hasSuffix(" km"))
    }

    func testCrossingAMileMovesTheHeadlineToTheNextOne() {
        let r = makeRecorder()
        r.start(unit: .miles)
        r.ingest(fix(0, at: 1))
        clock = clock.addingTimeInterval(600)
        r.ingest(fix(1609.344 + 20, at: 601))
        let s = RunActivityController.state(for: r)
        XCTAssertEqual(s.splitIndex, 2, "20 m past the first milepost is mile 2")
        XCTAssertEqual(s.splitFraction, 0.01, accuracy: 0.011)
        XCTAssertEqual(s.distanceText(unit: .miles), "1.01 mi")
        XCTAssertEqual(s.splitText(unit: .miles), "Mile 2")
        XCTAssertEqual(s.trackDescription(unit: .miles), "1 percent to Mile 3")
    }

    /// The pace shown falls back to the finished split, never the drifting
    /// run average, so the card is quiet between fixes.
    func testNewSplitBorrowsThePaceOfTheFinishedOne() {
        let r = makeRecorder()
        r.start(unit: .miles)
        r.ingest(fix(0, at: 1))
        clock = clock.addingTimeInterval(600)
        // 600 s over 1614.344 m, pro-rated at the boundary: the mile itself
        // took 598 s, so the finished split prices at 9:58.
        r.ingest(fix(1609.344 + 5, at: 601))
        let s = RunActivityController.state(for: r)
        XCTAssertNil(s.splitPace, "5 m is too little to price mile 2")
        XCTAssertEqual(s.previousSplitPace ?? 0, 598, accuracy: 2)
        XCTAssertEqual(s.distanceText(unit: .miles), "1.00 mi")
        XCTAssertEqual(s.detailText(unit: .miles), "Mile 2 · 9:58 /mi")

        clock = clock.addingTimeInterval(1)
        r.refreshElapsed()
        XCTAssertEqual(s, RunActivityController.state(for: r))
    }

    /// The compact island has to stay short past ten miles, so the second
    /// decimal is dropped there rather than letting the text truncate.
    func testLongRunsDropADecimalSoTheIslandStillFits() {
        var s = RunActivityController.state(for: {
            let r = RunRecorder(now: { Date(timeIntervalSince1970: 1_700_000_000) })
            r.start(unit: .miles)
            return r
        }())
        s.distanceUnits = 9.99
        XCTAssertEqual(s.distanceText(unit: .miles), "9.99 mi")
        s.distanceUnits = 12.34
        XCTAssertEqual(s.distanceText(unit: .miles), "12.3 mi")
        XCTAssertLessThanOrEqual(s.distanceText(unit: .miles).count, 7)
    }

    func testKilometersUseTheirOwnNoun() {
        let r = makeRecorder()
        r.start(unit: .kilometers)
        r.ingest(fix(0, at: 1))
        clock = clock.addingTimeInterval(300)
        r.ingest(fix(1250, at: 301))
        let s = RunActivityController.state(for: r)
        XCTAssertEqual(s.splitText(unit: .kilometers), "Kilometer 2")
        XCTAssertEqual(s.distanceText(unit: .kilometers), "1.25 km")
        XCTAssertEqual(s.splitFraction, 0.25, accuracy: 0.011)
    }

    func testPausingFreezesTheClockAndResumingRestartsItFromTheSameElapsed() {
        let r = makeRecorder()
        r.start(unit: .miles)
        clock = clock.addingTimeInterval(90)
        r.pause()
        let paused = RunActivityController.state(for: r)
        XCTAssertTrue(paused.isPaused)
        XCTAssertEqual(paused.clock, .paused(elapsed: 90))

        clock = clock.addingTimeInterval(60)   // a minute at the light
        r.resume()
        let resumed = RunActivityController.state(for: r)
        XCTAssertFalse(resumed.isPaused)
        // The anchor is "now minus 90 s" so the widget's clock picks up at 1:30.
        XCTAssertEqual(resumed.clock, .running(since: clock.addingTimeInterval(-90)))
    }

    func testStateIsStableAcrossTicksThatChangeNothingVisible() {
        let r = makeRecorder()
        r.start(unit: .miles)
        r.ingest(fix(0, at: 1))
        clock = clock.addingTimeInterval(30)
        r.ingest(fix(100, at: 31))
        let a = RunActivityController.state(for: r)
        clock = clock.addingTimeInterval(1)
        r.refreshElapsed()
        let b = RunActivityController.state(for: r)
        XCTAssertEqual(a, b, "a second passing with no new fix must not be an update")
        XCTAssertNil(b.previousSplitPace, "no split has finished yet")
    }
}

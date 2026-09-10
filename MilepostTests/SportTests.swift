import CoreLocation
import XCTest
@testable import Milepost

/// Walks and rides go through the same engine as a run. What changes is what
/// counts as a plausible speed and how the rate is phrased, so that is what
/// these cover.
@MainActor
final class SportTests: XCTestCase {

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

    private func fix(_ metersNorth: Double, at seconds: TimeInterval, speed: CLLocationSpeed = -1) -> CLLocation {
        let lat = Self.baseLatitude + metersNorth / Self.metersPerDegree
        return CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: -73.97),
                          altitude: 10, horizontalAccuracy: 5, verticalAccuracy: 5,
                          course: 0, speed: speed,
                          timestamp: Date(timeIntervalSince1970: 1_700_000_000 + seconds))
    }

    /// Distance, splits and milestones are sport-independent; only the label
    /// changes. A 3 mile ride still books 3 splits.
    func testARideRecordsDistanceAndSplitsLikeAnythingElse() {
        let r = makeRecorder()
        r.start(unit: .miles, sport: .bike)
        r.ingest(fix(0, at: 1))
        clock = clock.addingTimeInterval(400)
        r.ingest(fix(3 * 1609.344, at: 401))   // 3 miles at about 27 mph
        XCTAssertEqual(r.distanceMeters, 3 * 1609.344, accuracy: 2)
        XCTAssertEqual(r.splits.count, 4, "three finished miles plus the one in progress")
        XCTAssertEqual(r.splits[0].distanceMeters, 1609.344, accuracy: 0.01)
        XCTAssertTrue(r.hasMovement)
    }

    /// 36 mph down a hill is ordinary on a bike and impossible on foot. The
    /// run bounds throw it away, which would have shown "-:--" for the
    /// fastest part of a ride.
    func testBikeSpeedsAreOnlyPlausibleForARide() {
        let descending = 100.0   // seconds per mile, about 36 mph
        let onABike = Pace.secondsPerUnit(distanceMeters: 1609.344, seconds: descending, unit: .miles, sport: .bike)
        XCTAssertEqual(onABike ?? 0, descending, accuracy: 0.5)
        XCTAssertNil(Pace.secondsPerUnit(distanceMeters: 1609.344, seconds: descending, unit: .miles, sport: .run),
                     "no run goes 36 mph")
    }

    /// A slow stroll is 45 minutes a mile. The run bounds stop at 40 and
    /// would leave a walker staring at "-:--".
    func testSlowWalksStayPlausible() {
        let strolling = 45.0 * 60
        XCTAssertNotNil(Pace.secondsPerUnit(distanceMeters: 1609.344, seconds: strolling, unit: .miles, sport: .walk))
        XCTAssertNil(Pace.secondsPerUnit(distanceMeters: 1609.344, seconds: strolling, unit: .miles, sport: .run))
    }

    /// Rides read in miles per hour; runs and walks read in minutes per mile.
    func testRatesAreFormattedPerSport() {
        let secondsPerMile = 4.0 * 60   // 15 mph
        XCTAssertEqual(Sport.bike.rateText(secondsPerMile, unit: .miles), "15.0")
        XCTAssertEqual(Sport.bike.rateSuffix(unit: .miles), "mph")
        XCTAssertEqual(Sport.bike.rateLabel("Avg.", unit: .miles), "Avg. speed (mph)")

        XCTAssertEqual(Sport.run.rateText(secondsPerMile, unit: .miles), "4:00")
        XCTAssertEqual(Sport.run.rateSuffix(unit: .miles), "/mi")
        XCTAssertEqual(Sport.walk.rateLabel("Avg.", unit: .miles), "Avg. pace (/mi)")

        XCTAssertEqual(Sport.bike.rateSuffix(unit: .kilometers), "km/h")
        XCTAssertEqual(Sport.bike.rateText(nil, unit: .miles), "-.-")
    }

    /// The voice says "14.2 miles per hour" on a ride, not "4 minutes 14
    /// seconds per mile".
    func testVoiceCuesFollowTheSport() {
        let ride = Milestone(distanceMeters: DistanceUnit.miles.meters, elapsed: 4 * 60, unit: .miles, sport: .bike)
        let phrase = VoiceCuePhrase.text(for: ride)
        XCTAssertTrue(phrase.contains("One mile."), phrase)
        XCTAssertTrue(phrase.contains("Average speed, 15.0 miles per hour."), phrase)

        let walk = Milestone(distanceMeters: DistanceUnit.miles.meters, elapsed: 18 * 60, unit: .miles, sport: .walk)
        XCTAssertTrue(VoiceCuePhrase.text(for: walk).contains("Average pace, 18 minutes per mile."))
    }

    /// Default titles and stored activities carry the sport.
    func testTitlesAndStorageCarryTheSport() {
        let morning = Date(timeIntervalSince1970: 1_700_000_000)   // 22:13 UTC
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(Format.defaultTitle(for: morning, sport: .bike, calendar: cal), "Night Ride")
        XCTAssertEqual(Format.defaultTitle(for: morning, sport: .walk, calendar: cal), "Night Walk")
        XCTAssertEqual(Format.defaultTitle(for: morning, calendar: cal), "Night Run")
    }

    /// The Live Activity shows a ride in mph and names it correctly.
    func testTheLiveActivityCardReadsAsARide() {
        let r = makeRecorder()
        r.start(unit: .miles, sport: .bike)
        r.ingest(fix(0, at: 1))
        clock = clock.addingTimeInterval(240)
        r.ingest(fix(1609.344 + 100, at: 241))
        let s = RunActivityController.state(for: r)
        XCTAssertEqual(s.splitIndex, 2)
        // 100 m into mile 2, its own share of the 240 s works out at 15.9 mph.
        // Miles per hour, never minutes per mile: that is the whole point.
        XCTAssertEqual(s.distanceText(unit: .miles), "1.06 mi")
        XCTAssertEqual(s.detailText(unit: .miles, sport: .bike), "Mile 2 · 15.9 mph")
        XCTAssertEqual(Sport.bike.symbol, "bicycle")
    }

    /// A ride that stops at a light and resumes keeps the clock honest, the
    /// same way a run does.
    func testPauseAndResumeOnARide() {
        let r = makeRecorder()
        r.start(unit: .miles, sport: .bike)
        r.ingest(fix(0, at: 1))
        clock = clock.addingTimeInterval(60)
        r.ingest(fix(400, at: 61))
        r.pause()
        XCTAssertEqual(r.elapsed, 60, accuracy: 0.01)
        clock = clock.addingTimeInterval(120)   // waiting at the light
        r.resume()
        // The pause drops the anchor, so the first fix after a resume only
        // re-anchors: the 400 m covered while stopped must not be booked.
        r.ingest(fix(400, at: 181))
        XCTAssertEqual(r.distanceMeters, 400, accuracy: 2)
        clock = clock.addingTimeInterval(60)
        r.ingest(fix(800, at: 241))
        r.refreshElapsed()
        XCTAssertEqual(r.elapsed, 120, accuracy: 0.01, "the wait must not count as riding time")
        XCTAssertEqual(r.distanceMeters, 800, accuracy: 2)
        XCTAssertEqual(r.sport, .bike)
    }
}

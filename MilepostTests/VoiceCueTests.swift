import CoreLocation
import XCTest
@testable import Milepost

@MainActor
final class VoiceCueTests: XCTestCase {

    private var clock = Date(timeIntervalSince1970: 1_700_000_000)
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

    private func recorder(collecting into: @escaping (Milestone) -> Void) -> RunRecorder {
        let r = RunRecorder(now: { [unowned self] in self.clock })
        r.onMilestone = into
        return r
    }

    // MARK: Engine

    func testHalfUnitBoundaryFiresOnceWithProRatedTime() {
        var seen: [Milestone] = []
        let r = recorder { seen.append($0) }
        r.start(unit: .miles)
        r.ingest(fix(0, at: 0))
        clock = clock.addingTimeInterval(360)
        r.ingest(fix(900, at: 360))                    // 6:00 for 900 m, crosses 804.67 m
        XCTAssertEqual(seen.count, 1)
        XCTAssertEqual(seen[0].distanceMeters, DistanceUnit.miles.meters / 2, accuracy: 0.001)
        XCTAssertEqual(seen[0].units, 0.5)
        XCTAssertEqual(seen[0].elapsed, 360 * (804.672 / 900), accuracy: 1)
        XCTAssertEqual(seen[0].unit, .miles)
        // The next fix short of the mile fires nothing more.
        clock = clock.addingTimeInterval(60)
        r.ingest(fix(1000, at: 420))
        XCTAssertEqual(seen.count, 1)
    }

    func testOneLongStepEmitsEveryBoundaryInOrder() {
        var seen: [Milestone] = []
        let r = recorder { seen.append($0) }
        r.start(unit: .kilometers)
        r.ingest(fix(0, at: 0))
        clock = clock.addingTimeInterval(600)
        r.ingest(fix(1700, at: 600))
        XCTAssertEqual(seen.map(\.units), [0.5, 1, 1.5])
        XCTAssertEqual(seen[0].elapsed, 600 * 500 / 1700, accuracy: 1)
        XCTAssertEqual(seen[1].elapsed, 600 * 1000 / 1700, accuracy: 1)
        XCTAssertEqual(seen[2].elapsed, 600 * 1500 / 1700, accuracy: 1)
        XCTAssertEqual(seen[1].averagePace!, 600 * 1000 / 1700, accuracy: 2)
    }

    func testMilestonesRestartOnEachRun() {
        var seen: [Milestone] = []
        let r = recorder { seen.append($0) }
        r.start(unit: .kilometers)
        r.ingest(fix(0, at: 0))
        clock = clock.addingTimeInterval(200)
        r.ingest(fix(600, at: 200))
        XCTAssertEqual(seen.map(\.units), [0.5])
        r.discard()
        r.start(unit: .kilometers)
        r.ingest(fix(0, at: 300))
        clock = clock.addingTimeInterval(200)
        r.ingest(fix(600, at: 500))
        XCTAssertEqual(seen.map(\.units), [0.5, 0.5], "A new run counts from zero again")
    }

    // MARK: Setting

    func testIntervalFilter() {
        XCTAssertFalse(VoiceCueInterval.off.includes(units: 1))
        XCTAssertFalse(VoiceCueInterval.full.includes(units: 0.5))
        XCTAssertTrue(VoiceCueInterval.full.includes(units: 1))
        XCTAssertTrue(VoiceCueInterval.full.includes(units: 3))
        XCTAssertTrue(VoiceCueInterval.half.includes(units: 0.5))
        XCTAssertTrue(VoiceCueInterval.half.includes(units: 2))
    }

    func testTitlesFollowTheUnit() {
        XCTAssertEqual(VoiceCueInterval.half.title(unit: .miles), "Every half mile")
        XCTAssertEqual(VoiceCueInterval.full.title(unit: .kilometers), "Every kilometer")
        XCTAssertEqual(VoiceCueInterval.off.title(unit: .kilometers), "Off")
    }

    // MARK: Phrase

    func testPhraseForEachDistanceShape() {
        XCTAssertEqual(VoiceCuePhrase.distance(0.5, unit: .miles), "Half mile.")
        XCTAssertEqual(VoiceCuePhrase.distance(1, unit: .miles), "One mile.")
        XCTAssertEqual(VoiceCuePhrase.distance(1.5, unit: .miles), "1 and a half miles.")
        XCTAssertEqual(VoiceCuePhrase.distance(3, unit: .kilometers), "3 kilometers.")
        XCTAssertEqual(VoiceCuePhrase.distance(2.5, unit: .kilometers), "2 and a half kilometers.")
    }

    func testSpokenDurations() {
        XCTAssertEqual(VoiceCuePhrase.spoken(seconds: 45), "45 seconds")
        XCTAssertEqual(VoiceCuePhrase.spoken(seconds: 60), "1 minute")
        XCTAssertEqual(VoiceCuePhrase.spoken(seconds: 9 * 60 + 5), "9 minutes 5 seconds")
        XCTAssertEqual(VoiceCuePhrase.spoken(seconds: 3600 + 120), "1 hour 2 minutes")
        XCTAssertEqual(VoiceCuePhrase.spoken(seconds: 0), "0 seconds")
    }

    func testFullPhraseIncludesPaceOnlyWhenPlausible() {
        let mile = Milestone(distanceMeters: DistanceUnit.miles.meters, elapsed: 9 * 60 + 12, unit: .miles)
        XCTAssertEqual(VoiceCuePhrase.text(for: mile),
                       "One mile. Time, 9 minutes 12 seconds. Average pace, 9 minutes 12 seconds per mile.")
        let jitter = Milestone(distanceMeters: DistanceUnit.miles.meters / 2, elapsed: 30, unit: .miles)
        XCTAssertEqual(VoiceCuePhrase.text(for: jitter), "Half mile. Time, 30 seconds.")
    }
}

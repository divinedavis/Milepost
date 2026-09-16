import CoreLocation
import HealthKit
import XCTest
@testable import MilepostWatch

/// Journeys through a workout on the watch.
///
/// watchOS has no XCUITest, so there is no way to press the buttons. What there
/// is, is the controller the buttons call — and every freeze and every lost run
/// this app has had lived there, not in the views. These drive it end to end.
///
/// Nothing here has a Health database behind it: the test host is unsigned, so
/// `HKWorkoutSession` never attaches. That is the point. A watch with Health
/// unavailable, or a user who refused the permission, must still get a run, and
/// that is exactly the case a real wrist never shows you until it does.
@MainActor
final class WatchWorkoutJourneyTests: XCTestCase {

    private var controller: WatchWorkoutController!
    /// The recorder's clock, injected so a journey can cover twelve minutes of
    /// running in a millisecond of test. Without it every fixture fix is
    /// timestamped before the run began and the engine — rightly — throws them
    /// all away, leaving a journey that silently measures nothing.
    private var clock = Date(timeIntervalSince1970: 1_700_000_000)

    override func setUp() async throws {
        clock = Date(timeIntervalSince1970: 1_700_000_000)
        controller = WatchWorkoutController(recorder: RunRecorder(now: { [unowned self] in self.clock }))
    }

    override func tearDown() async throws {
        controller = nil
    }

    // MARK: Fixtures

    private let origin = CLLocationCoordinate2D(latitude: 40.6602, longitude: -73.9690)

    /// A fix `metersNorth` up the meridian, taken at the current clock.
    private func fix(_ metersNorth: Double, speed: CLLocationSpeed = 3.2) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: origin.latitude + metersNorth / 111_320,
                                                      longitude: origin.longitude),
                   altitude: 12, horizontalAccuracy: 5, verticalAccuracy: 4,
                   course: 0, speed: speed,
                   timestamp: clock)
    }

    /// Covers ground, the way the location service would, advancing the clock
    /// with it so pace and splits are computed from real elapsed time.
    private func run(meters: Double, over seconds: TimeInterval, step: Double = 50) {
        let steps = max(1, Int((meters / step).rounded()))
        let perStep = seconds / Double(steps)
        var covered = 0.0
        controller.recorder.ingest(fix(0))
        for _ in 0..<steps {
            covered += step
            clock = clock.addingTimeInterval(perStep)
            controller.recorder.ingest(fix(covered, speed: step / perStep))
        }
        controller.recorder.refreshElapsed()
    }

    // MARK: Journeys

    /// Pressing Run has to start a run. This is the regression test for the
    /// freeze: start used to be async and sat behind the workout session, so
    /// with Health unavailable the screen never changed at all.
    func testStartBeginsRecordingImmediatelyWithoutHealth() {
        XCTAssertEqual(controller.phase, .idle)
        controller.start(sport: .run, unit: .miles)
        // Synchronously, on the same run loop pass — no awaiting, no polling.
        XCTAssertEqual(controller.phase, .running, "Start must move to the live screen at once")
        XCTAssertEqual(controller.recorder.state, .recording)
        XCTAssertEqual(controller.recorder.sport, .run)
        XCTAssertEqual(controller.recorder.unit, .miles)
        XCTAssertNotNil(controller.recorder.startDate)
        XCTAssertTrue(controller.location.isTracking, "GPS has to be on or nothing is measured")
    }

    func testStartIsIgnoredWhileAlreadyRecording() {
        controller.start(sport: .run, unit: .miles)
        let started = controller.recorder.startDate
        controller.start(sport: .bike, unit: .kilometers)
        XCTAssertEqual(controller.recorder.sport, .run, "a second press must not restart the run")
        XCTAssertEqual(controller.recorder.startDate, started)
    }

    /// The full journey: start, cover ground, pause, resume, end — and get a
    /// payload for the phone, with no Health session anywhere in it.
    func testFullRunJourneyProducesAPayloadWithoutHealth() async {
        controller.start(sport: .run, unit: .miles)
        run(meters: 2400, over: 600)
        XCTAssertGreaterThan(controller.recorder.distanceMeters, 2000)

        controller.pause()
        XCTAssertEqual(controller.phase, .paused)
        XCTAssertEqual(controller.recorder.state, .paused)

        controller.resume()
        XCTAssertEqual(controller.phase, .running)

        let payload = await controller.end()
        XCTAssertNotNil(payload, "a run recorded without Health still has to reach the phone")
        XCTAssertEqual(controller.phase, .finished)
        XCTAssertFalse(controller.location.isTracking, "GPS must be off once the run ends")

        guard let payload else { return }
        XCTAssertGreaterThan(payload.distanceMeters, 2000)
        XCTAssertGreaterThan(payload.movingSeconds, 0)
        XCTAssertFalse(payload.route.isEmpty, "the route is the phone's whole reason for wanting this")
        XCTAssertEqual(payload.sport, .run)
        XCTAssertFalse(payload.splits.isEmpty)
        // No session attached, so nothing was written to Health, and the phone
        // must not be told otherwise or it will skip writing it itself.
        XCTAssertNil(payload.healthWorkoutID)
    }

    func testEndingARunThatNeverMovedKeepsNothingAndResets() async {
        controller.start(sport: .walk, unit: .miles)
        controller.recorder.ingest(fix(0, speed: 0))
        let payload = await controller.end()
        XCTAssertNil(payload, "a run that never moved is not an activity")
        XCTAssertEqual(controller.phase, .idle, "and the watch has to be ready to start another")
        XCTAssertEqual(controller.recorder.state, .idle)
        XCTAssertFalse(controller.location.isTracking)
    }

    func testEndingIsIgnoredWhenNothingIsRunning() async {
        let payload = await controller.end()
        XCTAssertNil(payload)
        XCTAssertEqual(controller.phase, .idle)
    }

    func testDiscardThrowsTheRunAwayAndReleasesGPS() {
        controller.start(sport: .run, unit: .miles)
        run(meters: 800, over: 200)
        controller.discard()
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(controller.recorder.state, .idle)
        XCTAssertEqual(controller.recorder.distanceMeters, 0)
        XCTAssertFalse(controller.location.isTracking)
        XCTAssertNil(controller.finished)
    }

    /// Done on the summary screen: the watch has to come back to a clean start
    /// screen, or the next run begins on top of the last one's numbers.
    func testClearingTheSummaryReturnsToAUsableStartScreen() async {
        controller.start(sport: .run, unit: .miles)
        run(meters: 1200, over: 300)
        _ = await controller.end()
        XCTAssertEqual(controller.phase, .finished)
        XCTAssertNotNil(controller.finished)

        controller.clearFinished()
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertNil(controller.finished)
        XCTAssertEqual(controller.recorder.distanceMeters, 0)

        controller.start(sport: .bike, unit: .kilometers)
        XCTAssertEqual(controller.phase, .running, "the watch must be able to record again")
        XCTAssertEqual(controller.recorder.sport, .bike)
    }

    func testToggleMirrorsPauseAndResume() {
        controller.start(sport: .run, unit: .miles)
        controller.toggle()
        XCTAssertEqual(controller.phase, .paused)
        controller.toggle()
        XCTAssertEqual(controller.phase, .running)
    }

    /// A ride is measured in speed and files under cycling distance. Getting
    /// this wrong reads "-:--" for a whole ride, because the pace lands outside
    /// the run bounds.
    func testARideRecordsWithCyclingRulesAndReadsInSpeed() async {
        controller.start(sport: .bike, unit: .miles)
        run(meters: 8000, over: 900)          // ~32 km/h
        XCTAssertTrue(controller.recorder.sport.showsSpeed)
        XCTAssertNotNil(controller.recorder.averagePace, "a ride's rate must be inside the bike bounds")
        // A ride reads in mph, not minutes per mile. "19.9", never "3:01".
        let rate = Sport.bike.rateText(controller.recorder.averagePace, unit: .miles)
        XCTAssertFalse(rate.contains(":"), "a ride must read as speed, not pace — got \(rate)")
        XCTAssertEqual(Sport.bike.rateSuffix(unit: .miles), "mph")
        let payload = await controller.end()
        XCTAssertEqual(payload?.sport, .bike)
        XCTAssertEqual(Sport.bike.distanceQuantityType, HKQuantityType(.distanceCycling))
    }

    /// Splits come from the shared engine, so they must match what the phone
    /// would produce for the same ground.
    func testSplitsRollOverOnTheWatchExactlyAsOnThePhone() async {
        controller.start(sport: .run, unit: .miles)
        run(meters: 3300, over: 900)          // just over two miles
        let payload = await controller.end()
        let splits = payload?.splits ?? []
        let complete = splits.filter { $0.isComplete(splitMeters: DistanceUnit.miles.meters) }
        XCTAssertEqual(complete.count, 2, "two full miles of ground is two full splits")
        XCTAssertEqual(splits.map(\.index), Array(1...splits.count), "splits must be numbered in order")
    }

    /// Pauses travel to the phone and on into Health, which derives a workout's
    /// duration from them.
    func testPausesReachThePayload() async {
        controller.start(sport: .run, unit: .miles)
        run(meters: 800, over: 200)
        controller.pause()
        // A pause has to last for the clock to have anything to subtract; a
        // zero-length one is dropped on purpose, since HealthKit rejects a
        // pause and resume at the same instant.
        clock = clock.addingTimeInterval(120)
        controller.resume()
        run(meters: 800, over: 200)
        let payload = await controller.end()
        XCTAssertEqual(payload?.pauses.count, 1)
        XCTAssertEqual(payload?.pauses.first?.duration ?? 0, 120, accuracy: 1)
        // The gap between wall clock and moving time is exactly the pause.
        if let p = payload {
            let wall = p.endDate.timeIntervalSince(p.startDate)
            XCTAssertEqual(wall - p.movingSeconds, 120, accuracy: 2)
        }
    }

    // MARK: Remote control from the phone

    func testRouteWritingFollowsThePhoneAndStartsOff() {
        XCTAssertFalse(controller.includeRouteInHealth,
                       "a watch that has never heard from its phone must not write a route")
        XCTAssertEqual(controller.includeRouteInHealth, HealthSettings.routeDefault)
    }

    func testRemoteCommandsDecodeToTheActionsTheyName() {
        for command in [WorkoutRemoteCommand.pause, .resume, .end] {
            let decoded = WorkoutRemoteMessage.decode(WorkoutRemoteMessage.command(command).data)
            XCTAssertEqual(decoded, .command(command))
        }
        // A build that does not know a message ignores it rather than acting on
        // the wrong one — the watch and the phone update independently.
        XCTAssertNil(WorkoutRemoteMessage.decode(Data(#"{"detonate":{}}"#.utf8)))
    }

    func testMirroredStateCarriesWhatThePhoneDraws() {
        controller.start(sport: .run, unit: .miles)
        run(meters: 1600, over: 480)
        let snapshot = MirroredWorkoutState(sportRaw: controller.recorder.sport.rawValue,
                                            unitRaw: controller.recorder.unit.rawValue,
                                            distanceMeters: controller.recorder.distanceMeters,
                                            elapsed: controller.recorder.elapsed,
                                            paceSecondsPerUnit: controller.recorder.averagePace,
                                            heartRate: 152,
                                            activeKilocalories: 88,
                                            isPaused: false,
                                            elapsedAnchor: controller.recorder.elapsedAnchor)
        let back = WorkoutRemoteMessage.decode(WorkoutRemoteMessage.state(snapshot).data)
        XCTAssertEqual(back, .state(snapshot))
        XCTAssertGreaterThan(snapshot.distanceMeters, 1000)
    }
}

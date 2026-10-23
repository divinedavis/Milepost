import CoreLocation
import HealthKit
import SwiftData
import XCTest
@testable import Milepost

/// The run-in-progress autosave (2026-10-22): a phone that dies mid-run must
/// come back with the run saved, numbers as they were on screen at the last
/// write, and nothing extra.
@MainActor
final class RunAutosaveTests: XCTestCase {

    private var clock = Date(timeIntervalSince1970: 1_700_000_000)
    private var fileURL: URL!
    /// Held: a container released while its context is in use takes the
    /// test process down (see CLAUDE.md, Apple Watch).
    private var store: ModelContainer!

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("autosave-\(UUID().uuidString).json")
        store = try ModelContainer(for: Activity.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL)
        store = nil
    }

    private func makeRecorder() -> RunRecorder {
        RunRecorder(now: { [unowned self] in self.clock })
    }

    private func fix(_ metersNorth: Double, at seconds: TimeInterval) -> CLLocation {
        let lat = 40.68 + metersNorth / 111_000
        return CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: -73.97),
                          altitude: 10, horizontalAccuracy: 5, verticalAccuracy: 5,
                          course: 0, speed: -1,
                          timestamp: Date(timeIntervalSince1970: 1_700_000_000 + seconds))
    }

    /// A recorder 2 minutes into a walk, ~300 m covered.
    private func walking() -> RunRecorder {
        let r = makeRecorder()
        r.start(unit: .miles, sport: .walk)
        for (i, m) in [0.0, 100, 200, 300].enumerated() {
            clock = Date(timeIntervalSince1970: 1_700_000_000 + Double(i) * 40)
            r.ingest(fix(m, at: Double(i) * 40))
        }
        return r
    }

    private func activities() throws -> [Activity] {
        try store.mainContext.fetch(FetchDescriptor<Activity>())
    }

    func testIdleRecorderHasNoCheckpoint() {
        XCTAssertNil(makeRecorder().checkpoint())
    }

    func testCheckpointCarriesWhatTheScreenShows() throws {
        let r = walking()
        let cp = try XCTUnwrap(r.checkpoint())
        XCTAssertEqual(cp.sport, .walk)
        XCTAssertEqual(cp.distanceMeters, r.distanceMeters)
        XCTAssertEqual(cp.movingSeconds, r.elapsed)
        XCTAssertEqual(cp.route.count, r.route.count)
        XCTAssertEqual(cp.savedAt, clock)
    }

    func testRecoveredSummaryMatchesWhatFinishWouldHaveSaved() throws {
        let r = walking()
        let summary = try XCTUnwrap(r.checkpoint()?.summary)
        let finished = try XCTUnwrap(r.finish())
        XCTAssertEqual(summary.distanceMeters, finished.distanceMeters)
        XCTAssertEqual(summary.movingSeconds, finished.movingSeconds)
        XCTAssertEqual(summary.endDate, finished.endDate)
        XCTAssertEqual(summary.splits, finished.splits)
        XCTAssertEqual(summary.route, finished.route)
    }

    func testAnOpenPauseIsClosedAtTheLastWrite() throws {
        let r = walking()
        r.pause()
        clock.addTimeInterval(90)
        let summary = try XCTUnwrap(r.checkpoint()?.summary)
        XCTAssertEqual(summary.pauses.count, 1)
        XCTAssertEqual(summary.pauses[0].end, clock)
        XCTAssertEqual(summary.pauses[0].duration, 90, accuracy: 0.001)
    }

    func testARunThatNeverMovedIsNotRecovered() throws {
        let r = makeRecorder()
        r.start(unit: .miles)
        let autosave = RunAutosave(recorder: r, fileURL: fileURL)
        autosave.tick()
        autosave.flush()
        XCTAssertNotNil(autosave.pending(), "a still run is written; it just isn't saved")

        let recovery = RunRecovery()
        XCTAssertNil(recovery.recover(from: autosave, into: store.mainContext))
        autosave.flush()
        XCTAssertNil(recovery.recovered)
        XCTAssertTrue(try activities().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    /// The whole journey: recording, the process dies, the next launch.
    func testALeftoverCheckpointBecomesASavedActivityOnce() throws {
        let r = walking()
        let dying = RunAutosave(recorder: r, fileURL: fileURL)
        dying.tick()
        dying.flush()

        // Next launch: a fresh, idle recorder and a fresh autosave.
        let autosave = RunAutosave(recorder: makeRecorder(), fileURL: fileURL)
        autosave.flush()
        let recovery = RunRecovery()
        let activity = try XCTUnwrap(recovery.recover(from: autosave, into: store.mainContext))
        autosave.flush()

        XCTAssertEqual(activity.sport, .walk)
        XCTAssertEqual(activity.distanceMeters, r.distanceMeters, accuracy: 0.001)
        XCTAssertEqual(recovery.recovered?.activityID, activity.id)
        XCTAssertEqual(try activities().count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path), "recovered once, then cleared")

        // A third launch finds nothing.
        XCTAssertNil(RunRecovery().recover(from: autosave, into: store.mainContext))
        XCTAssertEqual(try activities().count, 1)
    }

    /// At launch the recorder is idle and the file is the previous run's.
    /// The timer must not delete it before recovery runs.
    func testAnIdleTickAtLaunchLeavesThePreviousRunAlone() {
        let recorder = walking()  // held: the autosave keeps it weakly
        let dying = RunAutosave(recorder: recorder, fileURL: fileURL)
        dying.tick()
        dying.flush()
        let next = RunAutosave(recorder: makeRecorder(), fileURL: fileURL)
        next.tick()
        next.flush()
        XCTAssertNotNil(next.pending())
    }

    func testFinishingARunClearsItsFileOnTheNextTick() {
        let r = walking()
        let autosave = RunAutosave(recorder: r, fileURL: fileURL)
        autosave.tick()
        r.discard()
        autosave.tick()
        autosave.flush()
        XCTAssertNil(autosave.pending())
    }

    func testACheckpointFromAnotherLayoutVersionIsIgnored() throws {
        var cp = try XCTUnwrap(walking().checkpoint())
        cp.version = RunCheckpoint.currentVersion + 1
        let autosave = RunAutosave(recorder: makeRecorder(), fileURL: fileURL)
        autosave.write(cp)
        autosave.flush()
        XCTAssertNil(autosave.pending())
    }

    // MARK: Daily steps

    func testDailyMovementIsNewestFirstWithNoHoles() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let today = calendar.startOfDay(for: now)
        let twoAgo = calendar.date(byAdding: .day, value: -2, to: today)!
        let days = DailyMovement.days(4, endingOn: now, calendar: calendar,
                                      steps: [today: 5_000, twoAgo: 9_000],
                                      distance: [today: 3_700])
        XCTAssertEqual(days.map(\.day), (0..<4).map { calendar.date(byAdding: .day, value: -$0, to: today)! })
        XCTAssertEqual(days.map(\.steps), [5_000, nil, 9_000, nil])
        XCTAssertEqual(days[0].distanceMeters, 3_700)
        XCTAssertNil(days[2].distanceMeters)
    }

    func testDailyStepsAreOffByDefaultAndAskForReadsOnly() {
        XCTAssertFalse(HealthSettings.dailyDefault)
        XCTAssertEqual(HealthKitService.dailyReadTypes,
                       [HKQuantityType(.stepCount), HKQuantityType(.distanceWalkingRunning)])
    }
}

/// The Profile map draws hundreds of routes; each is thinned first.
final class RouteLineTests: XCTestCase {
    private func line(_ n: Int) -> [CLLocationCoordinate2D] {
        (0..<n).map { CLLocationCoordinate2D(latitude: 40 + Double($0) * 1e-5, longitude: -73) }
    }

    func testShortRoutesAreUntouched() {
        XCTAssertEqual(RouteLine.thin(line(10), to: 250).count, 10)
    }

    func testLongRoutesAreCappedAndKeepBothEnds() {
        let points = line(3_601)
        let thin = RouteLine.thin(points, to: 250)
        XCTAssertLessThanOrEqual(thin.count, 251)
        XCTAssertGreaterThan(thin.count, 200)
        XCTAssertEqual(thin.first?.latitude, points.first?.latitude)
        XCTAssertEqual(thin.last?.latitude, points.last?.latitude)
    }

    func testStrollerRunsAreRunsOnTheMap() {
        XCTAssertEqual(Sport.strollerRun.mapGroup, .run)
        XCTAssertEqual(Sport.walk.mapGroup, .walk)
    }
}

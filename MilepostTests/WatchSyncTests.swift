import CoreLocation
import SwiftData
import XCTest
@testable import Milepost

/// The watch → phone hand-off. None of this needs a watch: the payload, the
/// import and the remote-control protocol are all plain values.
@MainActor
final class WatchSyncTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func summary(sport: Sport = .run, paused: Bool = false) -> RunSummary {
        let route = [
            RoutePoint(latitude: 40.68, longitude: -73.97, timestamp: start,
                       altitude: 12, horizontalAccuracy: 5, verticalAccuracy: 3,
                       speed: 3.2, cumulativeMeters: 0),
            RoutePoint(latitude: 40.69, longitude: -73.97, timestamp: start.addingTimeInterval(600),
                       altitude: 18, horizontalAccuracy: 5, verticalAccuracy: 3,
                       speed: 3.2, cumulativeMeters: 1920),
        ]
        return RunSummary(startDate: start,
                          endDate: start.addingTimeInterval(700),
                          movingSeconds: 600,
                          distanceMeters: 1920,
                          splitMeters: DistanceUnit.miles.meters,
                          route: route,
                          splits: [Split(index: 1, distanceMeters: 1609.344, seconds: 503),
                                   Split(index: 2, distanceMeters: 310, seconds: 97)],
                          sport: sport,
                          pauses: paused ? [PauseInterval(start: start.addingTimeInterval(300),
                                                          end: start.addingTimeInterval(400))] : [])
    }

    /// The container has to be held for as long as the context is used.
    /// `try makeContainer().mainContext` looks harmless and takes the whole
    /// test process down inside SwiftData: the context does not keep its
    /// container alive.
    private var store: ModelContainer!

    private func context() throws -> ModelContext {
        store = try ModelContainer(for: Activity.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return store.mainContext
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    func testPayloadSurvivesTheTripIntact() throws {
        let payload = WatchActivityPayload(title: "Morning Run", summary: summary(paused: true),
                                           averageHeartRate: 148, maxHeartRate: 171,
                                           activeKilocalories: 212, healthWorkoutID: UUID().uuidString)
        let data = try JSONEncoder().encode(payload)
        let back = try JSONDecoder().decode(WatchActivityPayload.self, from: data)
        XCTAssertEqual(back, payload)
        // The route is the whole point of the phone copy — it is the one thing
        // the Health workout on the watch cannot hand back to the app.
        XCTAssertEqual(back.route.count, 2)
        XCTAssertEqual(back.pauses.count, 1)
        XCTAssertEqual(back.schema, WatchActivityPayload.currentSchema)
    }

    func testImportStoresTheActivityWithEverythingTheWatchMeasured() throws {
        let context = try context()
        let workoutID = UUID().uuidString
        let payload = WatchActivityPayload(title: "Evening Ride", summary: summary(sport: .bike, paused: true),
                                           averageHeartRate: 132, activeKilocalories: 300,
                                           healthWorkoutID: workoutID)

        let activity = WatchActivityImporter.store(payload, in: context)
        XCTAssertNotNil(activity)
        XCTAssertEqual(activity?.sport, .bike)
        XCTAssertEqual(activity?.title, "Evening Ride")
        XCTAssertEqual(activity?.route.count, 2)
        XCTAssertEqual(activity?.pauses.count, 1)
        // The watch already wrote the workout. Without this the phone writes a
        // second one and Health shows the ride twice.
        XCTAssertEqual(activity?.healthWorkoutID, workoutID)
        XCTAssertTrue(activity?.isInAppleHealth == true)
    }

    /// WatchConnectivity retries a transfer it never saw acknowledged, so the
    /// same run really does arrive twice.
    func testImportingTheSameActivityTwiceStoresItOnce() throws {
        let context = try context()
        let payload = WatchActivityPayload(title: "Morning Run", summary: summary())
        WatchActivityImporter.store(payload, in: context)
        WatchActivityImporter.store(payload, in: context)
        let stored = try context.fetch(FetchDescriptor<Activity>())
        XCTAssertEqual(stored.count, 1)
    }

    func testStoredActivityRebuildsTheSummaryItCameFrom() throws {
        let context = try context()
        let original = summary(paused: true)
        let payload = WatchActivityPayload(title: "Morning Run", summary: original)
        let activity = try XCTUnwrap(WatchActivityImporter.store(payload, in: context))
        // Health writes go through Activity.summary, so a round trip that lost
        // the pauses would silently put elapsed time into Health.
        XCTAssertEqual(activity.summary.pauses, original.pauses)
        XCTAssertEqual(activity.summary.distanceMeters, original.distanceMeters, accuracy: 0.001)
        XCTAssertEqual(activity.summary.sport, original.sport)
    }

    /// The friends backend must never see anything the watch measured. The
    /// shared payload is built from `Activity`, and `Activity` has nowhere to
    /// put heart rate or calories — this is the test that keeps it that way.
    func testAWatchActivityStillSharesStatsOnly() throws {
        let context = try context()
        let payload = WatchActivityPayload(title: "Morning Run", summary: summary(),
                                           averageHeartRate: 155, maxHeartRate: 180,
                                           activeKilocalories: 260,
                                           healthWorkoutID: UUID().uuidString)
        let activity = try XCTUnwrap(WatchActivityImporter.store(payload, in: context))
        let shared = try XCTUnwrap(SharedActivityPayload(activity: activity, userID: UUID()))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(shared)) as? [String: Any])
        XCTAssertEqual(Set(json.keys), ["user_id", "id", "sport", "title", "start_date", "distance_m", "moving_s"],
                       "a heart rate, calorie or route key here would leak health data")
    }

    // MARK: Remote control

    func testRemoteMessagesRoundTrip() throws {
        for command in [WorkoutRemoteCommand.pause, .resume, .end] {
            XCTAssertEqual(WorkoutRemoteMessage.decode(WorkoutRemoteMessage.command(command).data),
                           .command(command))
        }
        let snapshot = MirroredWorkoutState(sportRaw: Sport.walk.rawValue,
                                            unitRaw: DistanceUnit.kilometers.rawValue,
                                            distanceMeters: 2400, elapsed: 1500,
                                            paceSecondsPerUnit: 625, heartRate: 118,
                                            activeKilocalories: 140, isPaused: false,
                                            elapsedAnchor: start)
        XCTAssertEqual(WorkoutRemoteMessage.decode(WorkoutRemoteMessage.state(snapshot).data),
                       .state(snapshot))
    }

    /// A build that does not know a message must ignore it, not misread it as
    /// a different one — the watch and the phone update independently.
    func testUnknownRemoteMessageIsIgnored() {
        XCTAssertNil(WorkoutRemoteMessage.decode(Data(#"{"reverse":{}}"#.utf8)))
        XCTAssertNil(WorkoutRemoteMessage.decode(Data()))
    }
}

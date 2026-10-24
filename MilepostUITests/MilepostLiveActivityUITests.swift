import XCTest

/// The Dynamic Island card. It is drawn by SpringBoard, not the app, so the
/// assertions query SpringBoard after sending the app to the background.
/// Static location (run_tests.sh): the run never leaves mile 1.
final class MilepostLiveActivityUITests: XCTestCase {

    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uitest"]
        app.launch()
    }


    private func snap(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["MILEPOST_SHOTS"], !dir.isEmpty else { return }
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func tap(_ id: String, timeout: TimeInterval = 6) {
        let el = app.buttons[id]
        XCTAssertTrue(el.waitForExistence(timeout: timeout), "\(id) never appeared")
        el.tap()
    }

    private func startRun() {
        tap("record.start")
        allowLocation()
        if !app.buttons["live.pause"].waitForExistence(timeout: 4), app.buttons["record.start"].exists {
            tap("record.start")
        }
        XCTAssertTrue(app.buttons["live.pause"].waitForExistence(timeout: 8))
    }

    /// Any SpringBoard element whose label carries the text: the island's
    /// compact and expanded views are both static text to accessibility.
    private func islandText(_ text: String) -> XCUIElement {
        springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// Long-press the island to open the expanded card. The island sits
    /// about 32 pt down a 874 pt screen, so the press has to land there and
    /// not on the status bar above it.
    private func expandIsland() {
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.037))
            .press(forDuration: 1.2)
    }

    /// The Pause button on the expanded island has to actually pause the
    /// run, not just relabel the card: the intent runs in the app's process
    /// and reaches the live recorder.
    func testPausingFromTheDynamicIslandPausesTheRun() {
        startRun()
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(islandText("0.00 mi").waitForExistence(timeout: 10))

        expandIsland()
        let pause = springboard.buttons["island.pause"]
        XCTAssertTrue(pause.waitForExistence(timeout: 8), "no Pause button on the expanded island")
        snap("island-buttons")
        pause.tap()

        XCTAssertTrue(springboard.buttons["island.resume"].waitForExistence(timeout: 12),
                      "the card did not flip to Resume")

        app.activate()
        XCTAssertTrue(app.buttons["live.resume"].waitForExistence(timeout: 10),
                      "the island said paused but the recorder kept running")

        // And back the other way, from the island again.
        XCUIDevice.shared.press(.home)
        expandIsland()
        let resume = springboard.buttons["island.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 8))
        resume.tap()
        XCTAssertTrue(springboard.buttons["island.pause"].waitForExistence(timeout: 12))
        app.activate()
        XCTAssertTrue(app.buttons["live.pause"].waitForExistence(timeout: 10),
                      "the island said running but the recorder stayed paused")
    }

    func testDynamicIslandShowsTheMileAndFollowsPause() {
        startRun()

        // The compact island carries how far, not which mile: a mile number
        // would sit here unchanged for a whole mile.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(islandText("0.00 mi").waitForExistence(timeout: 10),
                      "no distance in the compact Dynamic Island after backgrounding")
        XCTAssertFalse(islandText("Mile 1").exists,
                       "the compact island is showing the mile number instead of the distance")
        snap("island-compact")

        // The expanded card is laid out like Now Playing: the mile in
        // progress under the distance, and the distance to the next milepost
        // at the end of the progress line (where a player shows time left).
        // "Milepost" and a bare "mi" would both match the app icon sitting on
        // the home screen behind it.
        expandIsland()
        XCTAssertTrue(islandText("Mile 1").waitForExistence(timeout: 6),
                      "the expanded island is missing the mile in progress")
        XCTAssertTrue(islandText("to Mile 2").exists, "no distance-to-the-next-mile on the progress line")
        XCTAssertTrue(springboard.buttons["island.pause"].exists, "no Pause button in the bottom row")
        snap("island-expanded")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()

        // Back in, pause, back out: the card should now say Paused.
        app.activate()
        tap("live.pause")
        XCTAssertTrue(app.buttons["live.resume"].waitForExistence(timeout: 4))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(islandText("Paused").waitForExistence(timeout: 10),
                      "the island did not pick up the pause")
        snap("island-paused")

        // Discarding the run must take the card down with it.
        app.activate()
        tap("live.finish")
        let discard = app.alerts.buttons["Discard"]
        XCTAssertTrue(discard.waitForExistence(timeout: 6))
        discard.tap()
        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 6))
        XCUIDevice.shared.press(.home)
        let gone = NSPredicate(format: "exists == false")
        let e = expectation(for: gone, evaluatedWith: islandText("0.00 mi"))
        wait(for: [e], timeout: 10)
        app.activate()
    }
}

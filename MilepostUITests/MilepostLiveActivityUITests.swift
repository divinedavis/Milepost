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

    private func allowLocation() {
        for label in ["Allow While Using App", "Allow Once", "Allow"] {
            let b = springboard.buttons[label]
            if b.waitForExistence(timeout: 3) { b.tap(); return }
        }
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

    func testDynamicIslandShowsTheMileAndFollowsPause() {
        startRun()

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(islandText("Mile 1").waitForExistence(timeout: 10),
                      "no Live Activity in the Dynamic Island after backgrounding")
        snap("island-compact")

        // The expanded card adds distance, pace and the track under the
        // mile. Assert on the distance: "Milepost" and a bare "mi" would
        // both match the app icon sitting on the home screen behind it.
        expandIsland()
        XCTAssertTrue(islandText("0.00 mi").waitForExistence(timeout: 6),
                      "the expanded island is missing the distance line")
        XCTAssertTrue(islandText("Time").exists, "no clock on the expanded card")
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
        let e = expectation(for: gone, evaluatedWith: islandText("Mile 1"))
        wait(for: [e], timeout: 10)
        app.activate()
    }
}

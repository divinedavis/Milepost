import XCTest

/// The Record panel pulls up into run options (2026-10-22, from a Strava
/// recording): auto-pause, voice, past routes, units, Apple Health, Settings.
final class MilepostRecordOptionsUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest"]
        app.launch()
    }

    func testPullingUpShowsOptionsAndPushingDownHidesThem() {
        let start = app.buttons["record.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertFalse(app.switches["record.option.autoPause"].exists, "options start hidden")
        XCTAssertTrue(app.buttons["record.moreOptions"].waitForExistence(timeout: 6))

        // Drag up from the panel.
        let from = start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 120, dy: 0))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: -220)),
                   withVelocity: .default, thenHoldForDuration: 0)
        XCTAssertTrue(app.switches["record.option.autoPause"].waitForExistence(timeout: 4), "drag up did not open the options")
        XCTAssertTrue(app.switches["record.option.voice"].exists)
        XCTAssertTrue(app.buttons["record.option.settings"].exists)

        // The handle closes it again (VoiceOver's way, and a plain tap).
        let handle = app.buttons["record.moreOptions"]
        XCTAssertEqual(handle.value as? String, "Expanded")
        handle.tap()
        XCTAssertFalse(app.switches["record.option.autoPause"].waitForExistence(timeout: 2))
        XCTAssertEqual(handle.value as? String, "Collapsed")
    }

    /// The panel follows the thumb and settles on the side it was let go:
    /// a short, slow pull falls back shut, a long one stays open, and a long
    /// slow push down closes it.
    func testThePanelSettlesWhereTheThumbLeavesIt() {
        let start = app.buttons["record.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        let grip = start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 120, dy: 0))
        let autoPause = app.switches["record.option.autoPause"]

        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: 0, dy: -40)),
                   withVelocity: .slow, thenHoldForDuration: 0.4)
        XCTAssertFalse(autoPause.waitForExistence(timeout: 2), "a short pull should fall back shut")
        // The pull started on History; a drag must not also press it.
        XCTAssertTrue(app.buttons["tab.record"].isSelected, "dragging from History switched tabs")

        grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: 0, dy: -300)),
                   withVelocity: .slow, thenHoldForDuration: 0.4)
        XCTAssertTrue(autoPause.waitForExistence(timeout: 4), "a long pull should stay open")
        XCTAssertEqual(app.buttons["record.moreOptions"].value as? String, "Expanded")

        // The panel grew, so the Start button moved up with it.
        let top = start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 120, dy: 0))
        top.press(forDuration: 0.05, thenDragTo: top.withOffset(CGVector(dx: 0, dy: 300)),
                  withVelocity: .slow, thenHoldForDuration: 0.4)
        XCTAssertFalse(autoPause.waitForExistence(timeout: 2), "a long push down should close it")
        XCTAssertEqual(app.buttons["record.moreOptions"].value as? String, "Collapsed")
    }

    /// An option set here is the same setting as in Profile > Settings.
    func testAutoPauseFromThePanelIsTheSameSetting() {
        let handle = app.buttons["record.moreOptions"]
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
        handle.tap()
        let toggle = app.switches["record.option.autoPause"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 4))
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")

        app.buttons["record.option.settings"].tap()
        let inSettings = app.switches["you.autoPause"]
        XCTAssertTrue(inSettings.waitForExistence(timeout: 6))
        XCTAssertEqual(inSettings.value as? String, "1")
        app.buttons["record.option.done"].tap()
        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 6))
    }

    func testTheOptionsGoAwayWhenARunStarts() {
        let handle = app.buttons["record.moreOptions"]
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
        handle.tap()
        XCTAssertTrue(app.switches["record.option.autoPause"].waitForExistence(timeout: 4))
        app.buttons["record.start"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once", "Allow"] where springboard.buttons[label].waitForExistence(timeout: 2) {
            springboard.buttons[label].tap(); break
        }
        XCTAssertTrue(app.buttons["live.pause"].waitForExistence(timeout: 10))
        app.buttons["live.collapse"].tap()
        XCTAssertFalse(app.switches["record.option.autoPause"].exists, "no options mid-run")
        XCTAssertFalse(app.buttons["record.moreOptions"].exists)
    }
}

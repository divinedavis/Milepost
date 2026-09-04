import XCTest

/// Flows that need no movement. The simulator sits at a fixed location for
/// these (run_tests.sh sets it), so "No Movement Detected" is the expected
/// end of every run here.
final class MilepostUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uitest"]
        app.launch()
    }

    /// The location prompt is a SpringBoard alert outside the app.
    private func allowLocation() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once", "Allow"] {
            let b = springboard.buttons[label]
            if b.waitForExistence(timeout: 3) { b.tap(); return }
        }
    }

    private func tap(_ id: String, timeout: TimeInterval = 6) {
        let el = app.buttons[id]
        XCTAssertTrue(el.waitForExistence(timeout: timeout), "\(id) never appeared")
        el.tap()
    }

    /// Start, allowing location the first time it is asked for.
    private func startRun() {
        tap("record.start")
        allowLocation()
        if !app.buttons["recorder.pause"].waitForExistence(timeout: 4), app.buttons["record.start"].exists {
            tap("record.start")
        }
        XCTAssertTrue(app.buttons["recorder.pause"].waitForExistence(timeout: 8))
    }

    func testEveryTabOpens() {
        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 8))

        tap("tab.activities")
        XCTAssertTrue(app.staticTexts["No runs yet"].waitForExistence(timeout: 6))

        tap("tab.you")
        XCTAssertTrue(app.staticTexts["This week"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Units"].exists)

        tap("tab.record")
        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.staticTexts["record.time"].label, "00:00")
        XCTAssertEqual(app.staticTexts["record.distance"].label, "0.00")
        XCTAssertEqual(app.staticTexts["record.pace"].label, "-:--")
    }

    /// Start opens the full-screen recorder with a running clock; Pause turns
    /// the header yellow and offers Resume + Finish; Finish with no movement
    /// shows the discard alert; Discard lands back on the map.
    func testStartPauseFinishWithoutMovementDiscards() {
        startRun()
        XCTAssertTrue(app.staticTexts["live.time"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.staticTexts["live.distance"].label, "0.00")
        XCTAssertEqual(app.staticTexts["live.pace"].label, "-:--")
        XCTAssertTrue(app.otherElements["splits.bar.1"].exists || app.staticTexts["Splits (mi)"].exists)

        // The clock runs.
        sleep(2)
        XCTAssertNotEqual(app.staticTexts["live.time"].label, "00:00:00")

        tap("recorder.pause")
        XCTAssertTrue(app.staticTexts["live.pausedBanner"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["recorder.resume"].exists)
        XCTAssertTrue(app.buttons["recorder.finish"].exists)

        let frozen = app.staticTexts["live.time"].label
        sleep(2)
        XCTAssertEqual(app.staticTexts["live.time"].label, frozen, "clock must stop while paused")

        tap("recorder.finish")
        let alert = app.alerts["No Movement Detected"]
        XCTAssertTrue(alert.waitForExistence(timeout: 6))
        alert.buttons["Discard"].tap()

        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["record.time"].label, "00:00")
    }

    /// Resume from the alert keeps the run going; collapsing shows the same
    /// run on the map card, and expanding gets the full screen back.
    func testResumeFromAlertAndCollapseExpand() {
        startRun()
        tap("recorder.pause")
        tap("recorder.finish")
        let alert = app.alerts["No Movement Detected"]
        XCTAssertTrue(alert.waitForExistence(timeout: 6))
        alert.buttons["Resume"].tap()
        XCTAssertTrue(app.buttons["recorder.pause"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["live.pausedBanner"].exists)

        tap("live.collapse")
        XCTAssertTrue(app.buttons["record.expand"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["recorder.pause"].exists, "map card keeps the controls while a run is live")
        XCTAssertFalse(app.buttons["record.start"].exists)

        tap("record.expand")
        XCTAssertTrue(app.staticTexts["live.time"].waitForExistence(timeout: 6))

        // Clean up so the next test starts idle.
        tap("recorder.pause")
        tap("recorder.finish")
        XCTAssertTrue(alert.waitForExistence(timeout: 6))
        alert.buttons["Discard"].tap()
        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 8))
    }

    func testUnitsSettingChangesLabels() {
        tap("tab.you")
        let picker = app.buttons["you.units"].exists ? app.buttons["you.units"] : app.otherElements["you.units"]
        XCTAssertTrue(picker.waitForExistence(timeout: 6))
        picker.tap()
        let km = app.buttons["Kilometers"]
        XCTAssertTrue(km.waitForExistence(timeout: 4))
        km.tap()

        tap("tab.record")
        XCTAssertTrue(app.staticTexts["Distance (km)"].waitForExistence(timeout: 6))

        // Put it back for the other tests (AppStorage persists across launches).
        tap("tab.you")
        picker.tap()
        let mi = app.buttons["Miles"]
        XCTAssertTrue(mi.waitForExistence(timeout: 4))
        mi.tap()
        tap("tab.record")
        XCTAssertTrue(app.staticTexts["Distance (mi)"].waitForExistence(timeout: 6))
    }
}

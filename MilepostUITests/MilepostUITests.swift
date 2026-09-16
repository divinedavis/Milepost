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

    /// Writes a PNG when TEST_RUNNER_MILEPOST_SHOTS points at a directory;
    /// otherwise a no-op. The simulator shares the host filesystem.
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

    /// Start, allowing location the first time it is asked for.
    private func startRun() {
        tap("record.start")
        allowLocation()
        if !app.buttons["live.pause"].waitForExistence(timeout: 4), app.buttons["record.start"].exists {
            tap("record.start")
        }
        XCTAssertTrue(app.buttons["live.pause"].waitForExistence(timeout: 8))
    }

    func testEveryTabOpens() {
        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 8))
        sleep(3)   // let the map tiles land before the marketing capture
        snap("record-idle")

        tap("tab.block")
        XCTAssertTrue(app.staticTexts["No activities yet"].waitForExistence(timeout: 6))

        tap("tab.you")
        XCTAssertTrue(app.staticTexts["This week"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Units"].exists)

        tap("tab.record")
        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.staticTexts["record.time"].label, "00:00")
        XCTAssertEqual(app.staticTexts["record.distance"].label, "0.00")
        XCTAssertEqual(app.staticTexts["record.pace"].label, "-:--")
        XCTAssertFalse(app.buttons["record.expand"].exists, "nothing to expand before a run starts")
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
        snap("live-recording")

        tap("live.pause")
        XCTAssertTrue(app.staticTexts["live.pausedBanner"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.buttons["live.resume"].exists)
        XCTAssertTrue(app.buttons["live.finish"].exists)
        snap("live-paused")

        let frozen = app.staticTexts["live.time"].label
        sleep(2)
        XCTAssertEqual(app.staticTexts["live.time"].label, frozen, "clock must stop while paused")

        tap("live.finish")
        let alert = app.alerts["No Movement Detected"]
        XCTAssertTrue(alert.waitForExistence(timeout: 6))
        snap("no-movement")
        alert.buttons["Discard"].tap()

        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["record.time"].label, "00:00")
    }

    /// Resume from the alert keeps the run going; collapsing shows the same
    /// run on the map card, and expanding gets the full screen back.
    func testResumeFromAlertAndCollapseExpand() {
        startRun()
        tap("live.pause")
        tap("live.finish")
        let alert = app.alerts["No Movement Detected"]
        XCTAssertTrue(alert.waitForExistence(timeout: 6))
        alert.buttons["Resume"].tap()
        XCTAssertTrue(app.buttons["live.pause"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.staticTexts["live.pausedBanner"].exists)

        tap("live.collapse")
        XCTAssertTrue(app.buttons["record.expand"].waitForExistence(timeout: 6))
        snap("map-recording")
        XCTAssertTrue(app.buttons["map.pause"].waitForExistence(timeout: 4), "map card keeps the controls while a run is live")
        XCTAssertFalse(app.buttons["record.start"].exists)

        tap("record.expand")
        XCTAssertTrue(app.staticTexts["live.time"].waitForExistence(timeout: 6))

        // Clean up so the next test starts idle.
        tap("live.pause")
        tap("live.finish")
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

    /// Apple Health starts off, and so does the route. Tapping the first
    /// toggle raises Apple's own permission sheet, which the runner cannot
    /// dismiss, so this checks the state around it instead of driving it.
    func testAppleHealthAndRouteBothStartOff() {
        tap("tab.you")
        app.swipeUp()
        let health = app.switches["you.healthEnabled"]
        XCTAssertTrue(health.waitForExistence(timeout: 6))
        XCTAssertEqual(health.value as? String, "0", "saving to Health must be opt-in")
        // The route switch is not even on screen until saving is on.
        XCTAssertFalse(app.switches["you.healthRoute"].exists)
    }

    func testRouteStaysOffWhenHealthIsTurnedOn() {
        app.terminate()
        app.launchArguments += ["-uitest-health-on"]
        app.launch()
        tap("tab.you")
        app.swipeUp()
        let route = app.switches["you.healthRoute"]
        XCTAssertTrue(route.waitForExistence(timeout: 6))
        // Allowing Health is not the same as agreeing to hand over a map of
        // where you run. This is the promise the You tab and the listing make.
        XCTAssertEqual(route.value as? String, "0")

        let footer = app.staticTexts["you.healthFooter"]
        XCTAssertTrue(footer.waitForExistence(timeout: 4))
        XCTAssertTrue(footer.label.contains("route is not written"), footer.label)

        route.switches.firstMatch.exists ? route.switches.firstMatch.tap() : route.tap()
        XCTAssertEqual(route.value as? String, "1")
        XCTAssertTrue(footer.label.contains("stays on this device"), footer.label)
    }

    func testVoiceCuesSettingEnablesPreviewAndPersists() {
        tap("tab.you")
        app.swipeUp()
        let toggle = app.switches["you.voiceEnabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 6))
        XCTAssertEqual(toggle.value as? String, "1")
        let picker = app.buttons["you.voiceCues"].exists ? app.buttons["you.voiceCues"] : app.otherElements["you.voiceCues"]
        XCTAssertTrue(picker.waitForExistence(timeout: 6))
        XCTAssertTrue(picker.label.contains("Every half mile"), picker.label)
        let preview = app.buttons["you.voicePreview"]
        XCTAssertTrue(preview.waitForExistence(timeout: 4))
        XCTAssertTrue(preview.isEnabled)
        preview.tap() // Speech is muted in UI tests.

        picker.tap()
        for title in ["Every half mile", "Every mile", "Every 2 miles", "Every 5 miles"] {
            XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 4))
        }
        app.buttons["Every 2 miles"].tap()
        XCTAssertTrue(picker.label.contains("Every 2 miles"), picker.label)

        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertFalse(preview.isEnabled)
        XCTAssertFalse(picker.isEnabled)

        tap("tab.record")
        tap("tab.you")
        app.swipeUp()
        XCTAssertTrue(toggle.waitForExistence(timeout: 6))
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertTrue(picker.label.contains("Every 2 miles"), picker.label)
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertTrue(preview.isEnabled)
        XCTAssertTrue(picker.isEnabled)
        XCTAssertTrue(picker.label.contains("Every 2 miles"), picker.label)
    }
}

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


    /// Profile keeps settings behind rows since 2026-10-22: open the tab,
    /// bring the row on screen, and push its screen.
    private func openProfileRow(_ id: String) {
        app.buttons["tab.you"].tap()
        let row = app.buttons[id]
        XCTAssertTrue(app.buttons["you.map"].waitForExistence(timeout: 8), "Profile never opened")
        for _ in 0..<8 where !(row.exists && row.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(row.isHittable, "\(id) never came on screen")
        row.tap()
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
        XCTAssertTrue(app.buttons["you.map"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["you.tileActivities"].exists)
        XCTAssertTrue(app.buttons["you.tileFriends"].exists)
        openProfileRow("you.rowSettings")
        XCTAssertTrue(app.staticTexts["Units"].waitForExistence(timeout: 6))

        tap("tab.record")
        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 6))
        // No stats card until a workout starts (owner, 2026-10-22).
        XCTAssertFalse(app.staticTexts["record.time"].exists, "a card of zeros before Start")
        XCTAssertFalse(app.staticTexts["record.distance"].exists)
        XCTAssertFalse(app.staticTexts["record.pace"].exists)
        XCTAssertFalse(app.buttons["record.expand"].exists, "nothing to expand before a run starts")
    }

    /// The simulator sits on a precise pinned fix, so once location is
    /// allowed the Record screen must say the GPS is ready.
    func testGPSStatusShowsReadyWithAFix() {
        startRun()
        tap("live.pause")
        tap("live.finish")
        let alert = app.alerts["No Movement Detected"]
        XCTAssertTrue(alert.waitForExistence(timeout: 6), "a pinned fix is a signal, so this is not the no-GPS alert")
        alert.buttons["Discard"].tap()
        let gps = app.descendants(matching: .any)["gps.status"]
        XCTAssertTrue(gps.waitForExistence(timeout: 8))
        let ready = NSPredicate(format: "label CONTAINS 'GPS ready'")
        expectation(for: ready, evaluatedWith: gps)
        waitForExpectations(timeout: 10)
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
        XCTAssertFalse(app.staticTexts["record.time"].exists, "the stats card leaves with the workout")
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
        openProfileRow("you.rowSettings")
        let picker = app.buttons["you.units"].exists ? app.buttons["you.units"] : app.otherElements["you.units"]
        XCTAssertTrue(picker.waitForExistence(timeout: 6))
        picker.tap()
        let km = app.buttons["Kilometers"]
        XCTAssertTrue(km.waitForExistence(timeout: 4))
        km.tap()

        // The Record tab shows no stats until a workout starts, so read
        // the unit off the live recorder, then throw the run away.
        tap("tab.record")
        startRun()
        XCTAssertTrue(app.staticTexts["Distance (km)"].waitForExistence(timeout: 6))
        discardRun()

        // Put it back for the other tests (AppStorage persists across launches).
        openProfileRow("you.rowSettings")
        XCTAssertTrue(picker.waitForExistence(timeout: 6))
        picker.tap()
        let mi = app.buttons["Miles"]
        XCTAssertTrue(mi.waitForExistence(timeout: 4))
        mi.tap()
        tap("tab.record")
        startRun()
        XCTAssertTrue(app.staticTexts["Distance (mi)"].waitForExistence(timeout: 6))
        discardRun()
    }

    /// Pause, Finish, Discard: the pinned simulator never moves.
    private func discardRun() {
        tap("live.pause")
        tap("live.finish")
        let alert = app.alerts["No Movement Detected"]
        XCTAssertTrue(alert.waitForExistence(timeout: 6))
        alert.buttons["Discard"].tap()
        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 8))
    }

    /// Apple Health starts off, and so does the route. Tapping the first
    /// toggle raises Apple's own permission sheet, which the runner cannot
    /// dismiss, so this checks the state around it instead of driving it.
    func testAppleHealthAndRouteBothStartOff() {
        openProfileRow("you.rowHealth")
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
        openProfileRow("you.rowHealth")
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

    /// Off by default; on, a run started standing still stops its own clock
    /// and says so in the banner.
    func testAutoPauseStartsOffAndPausesARunStandingStill() {
        openProfileRow("you.rowSettings")
        let toggle = app.switches["you.autoPause"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 6))
        XCTAssertEqual(toggle.value as? String, "0")
        // A full swipe can park this row under the navigation bar, where a
        // tap lands on the bar. Drag it back down into the open.
        if toggle.frame.minY < 160 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: 200)))
        }
        // The subtitle makes the cell tall and a centre tap lands on the text,
        // so tap the switch's end of the row. A tap while the list is still
        // settling is swallowed; try again until the value flips.
        for _ in 0..<3 where toggle.value as? String != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: toggle)], timeout: 2)
        }
        XCTAssertEqual(toggle.value as? String, "1")

        tap("tab.record")
        tap("record.start")
        allowLocation()
        if !app.buttons["live.collapse"].waitForExistence(timeout: 4), app.buttons["record.start"].exists {
            tap("record.start")
        }
        // Standing still, the run may already be auto-paused by the time the
        // recorder is on screen, so Pause is not a given here.
        let banner = app.staticTexts["live.pausedBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 25), "standing still never auto-paused")
        XCTAssertEqual(banner.label, "Auto-paused")
        XCTAssertTrue(app.buttons["live.resume"].exists)
        snap("live-autopaused")
    }

    func testVoiceCuesSettingEnablesPreviewAndPersists() {
        openProfileRow("you.rowSettings")
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
        openProfileRow("you.rowSettings")
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

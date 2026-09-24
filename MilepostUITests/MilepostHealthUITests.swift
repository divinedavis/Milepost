import XCTest

/// Journeys through the Apple Health surface.
///
/// The simulator runs these unsigned, so the app has no HealthKit entitlement
/// and nothing can actually be written. That is fine and is the point: what
/// these cover is that the settings say the right thing, that the promise about
/// routes holds, and that turning Health on does not disturb recording — which
/// is exactly what would break unnoticed, because a phone with Health working
/// hides it.
final class MilepostHealthUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uitest"]
        app.launch()
    }

    private func relaunch(healthOn: Bool) {
        app.terminate()
        app.launchArguments = ["-uitest"] + (healthOn ? ["-uitest-health-on"] : [])
        app.launch()
    }

    private func tap(_ id: String, timeout: TimeInterval = 6) {
        let el = app.buttons[id]
        XCTAssertTrue(el.waitForExistence(timeout: timeout), "\(id) never appeared")
        el.tap()
    }

    private func allowLocation() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once", "Allow"] {
            let b = springboard.buttons[label]
            if b.waitForExistence(timeout: 3) { b.tap(); return }
        }
    }

    private func openHealthSettings() {
        tap("tab.you")
        app.swipeUp()
    }

    private func toggle(_ id: String) -> XCUIElement { app.switches[id] }

    private func flip(_ id: String) {
        let t = toggle(id)
        XCTAssertTrue(t.waitForExistence(timeout: 6), "\(id) never appeared")
        t.switches.firstMatch.exists ? t.switches.firstMatch.tap() : t.tap()
    }

    /// The whole settings journey in one pass: off, on, route still off, route
    /// on, and the wording keeping up at each step.
    func testHealthSettingsJourney() {
        openHealthSettings()
        XCTAssertEqual(toggle("you.healthEnabled").value as? String, "0")
        XCTAssertFalse(toggle("you.healthRoute").exists, "the route switch is hidden until saving is on")
        var footer = app.staticTexts["you.healthFooter"]
        XCTAssertTrue(footer.waitForExistence(timeout: 4))
        XCTAssertTrue(footer.label.contains("count toward your rings"), footer.label)

        // Tapping the first switch raises Apple's permission sheet, which the
        // runner cannot dismiss, so the "on" state is set up at launch instead.
        relaunch(healthOn: true)
        openHealthSettings()
        XCTAssertEqual(toggle("you.healthEnabled").value as? String, "1")

        let route = toggle("you.healthRoute")
        XCTAssertTrue(route.waitForExistence(timeout: 6))
        XCTAssertEqual(route.value as? String, "0",
                       "allowing Health is not the same as agreeing to hand over where you run")
        footer = app.staticTexts["you.healthFooter"]
        XCTAssertTrue(footer.label.contains("route is not written"), footer.label)

        flip("you.healthRoute")
        XCTAssertEqual(route.value as? String, "1")
        XCTAssertTrue(footer.label.contains("stays on this device"), footer.label)

        // Leave the tab and come back: the choice has to survive, or someone
        // would set it every time they open the app.
        tap("tab.record")
        openHealthSettings()
        XCTAssertEqual(toggle("you.healthRoute").value as? String, "1")

        // And turning saving back off hides the route switch without silently
        // forgetting the answer.
        flip("you.healthEnabled")
        XCTAssertEqual(toggle("you.healthEnabled").value as? String, "0")
        XCTAssertFalse(toggle("you.healthRoute").exists)
        flip("you.healthEnabled")
        XCTAssertTrue(toggle("you.healthRoute").waitForExistence(timeout: 4))
        XCTAssertEqual(toggle("you.healthRoute").value as? String, "1", "the route answer was remembered")
    }

    /// Health on must not change how recording behaves. The save path now has
    /// an extra branch in it, and a short run is the one that exercises the
    /// branch and then throws the activity away.
    func testRecordingIsUnaffectedByHealthBeingOn() {
        relaunch(healthOn: true)
        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 8))
        tap("record.start")
        allowLocation()
        if !app.buttons["live.pause"].waitForExistence(timeout: 4), app.buttons["record.start"].exists {
            tap("record.start")
        }
        XCTAssertTrue(app.buttons["live.pause"].waitForExistence(timeout: 8))
        // Finish only exists while paused.
        tap("live.pause")
        XCTAssertTrue(app.staticTexts["live.pausedBanner"].waitForExistence(timeout: 4))
        tap("live.finish")
        // The simulator is pinned at one spot for this pass.
        let alert = app.alerts["No Movement Detected"]
        XCTAssertTrue(alert.waitForExistence(timeout: 8))
        alert.buttons["Discard"].tap()
        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 8))

        tap("tab.block")
        XCTAssertTrue(app.staticTexts["No activities yet"].waitForExistence(timeout: 8),
                      "a discarded run must not be stored, Health or no Health")
    }

    /// No paired watch, so the Record tab is the phone's own recorder and not a
    /// remote. If the banner ever showed up here, Start would be gone and the
    /// app would look broken to everyone without an Apple Watch.
    func testRecordTabIsNotAWatchRemoteWithoutAWatch() {
        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.otherElements["mirror.banner"].exists)
        XCTAssertFalse(app.buttons["mirror.toggle"].exists)
        XCTAssertFalse(app.buttons["mirror.end"].exists)
    }

    /// The Oura guide is reachable with Health off (someone arriving with a
    /// ring should find it before they know Health is the answer), and its
    /// first step tracks the real switch.
    func testOuraGuideTracksTheHealthSwitch() {
        openHealthSettings()
        tap("you.oura")
        var step = app.descendants(matching: .any)["oura.stepHealth"]
        XCTAssertTrue(step.waitForExistence(timeout: 6), "the Oura guide never opened")
        XCTAssertTrue(step.label.contains("Go back and turn on"), step.label)

        relaunch(healthOn: true)
        openHealthSettings()
        tap("you.oura")
        step = app.descendants(matching: .any)["oura.stepHealth"]
        XCTAssertTrue(step.waitForExistence(timeout: 6))
        XCTAssertTrue(step.label.contains("On."), step.label)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "oura-guide"
        shot.lifetime = .keepAlways
        add(shot)
    }
}

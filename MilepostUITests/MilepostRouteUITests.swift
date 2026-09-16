import XCTest

/// Needs the simulator to be moving: run_tests.sh starts a simctl location
/// route before this class runs. Start → distance climbs → Pause → Finish →
/// Save → the run shows up in Block with a route map.
final class MilepostRouteUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uitest"]
        app.launch()
    }

    private func allowLocation() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
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

    /// A real run saved with Apple Health switched on, all the way to the
    /// detail screen's Health entry.
    ///
    /// The simulator runs unsigned, so nothing can actually reach the Health
    /// database — what this covers is the path around it: saving still works
    /// with the extra branch in it, the activity is stored exactly once, and
    /// the menu offers to send it to Health because it has not been sent.
    func testSavingWithAppleHealthOnKeepsTheActivityAndOffersHealth() {
        app.terminate()
        app.launchArguments = ["-uitest", "-uitest-health-on"]
        app.launch()

        tap("record.start")
        allowLocation()
        if !app.buttons["live.pause"].waitForExistence(timeout: 4), app.buttons["record.start"].exists {
            tap("record.start")
        }
        XCTAssertTrue(app.buttons["live.pause"].waitForExistence(timeout: 8))

        let distance = app.staticTexts["live.distance"]
        let moved = NSPredicate(format: "label != '0.00'")
        wait(for: [expectation(for: moved, evaluatedWith: distance)], timeout: 45)

        tap("live.pause")
        tap("live.finish")
        XCTAssertTrue(app.textFields["save.title"].waitForExistence(timeout: 8), "save sheet never appeared")
        tap("save.save")
        XCTAssertTrue(app.staticTexts["celebrate.title"].waitForExistence(timeout: 8))
        tap("celebrate.done")

        tap("tab.block")
        let row = app.staticTexts["block.rowTitle"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "the run was not saved with Health on")
        XCTAssertEqual(app.staticTexts.matching(identifier: "block.rowTitle").count, 1,
                       "saving to Health must not store the activity twice")
        row.tap()
        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 8))

        tap("detail.menu")
        let sendToHealth = app.buttons["detail.saveToHealth"]
        XCTAssertTrue(sendToHealth.waitForExistence(timeout: 4),
                      "an activity not yet in Health should offer to go there")
        sendToHealth.tap()

        // Unsigned, so the write is refused. The activity has to survive that
        // without a crash and without losing anything.
        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.staticTexts["Distance"].exists)

        tap("detail.menu")
        tap("detail.delete")
        let confirm = app.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 4))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["No activities yet"].waitForExistence(timeout: 8))
    }

    func testMovingRunSavesAndAppearsInBlock() {
        tap("record.start")
        allowLocation()
        if !app.buttons["live.pause"].waitForExistence(timeout: 4), app.buttons["record.start"].exists {
            tap("record.start")
        }
        XCTAssertTrue(app.buttons["live.pause"].waitForExistence(timeout: 8))

        // Distance should tick up within a few fixes at the simulated speed.
        let distance = app.staticTexts["live.distance"]
        let moved = NSPredicate(format: "label != '0.00'")
        let e = expectation(for: moved, evaluatedWith: distance)
        wait(for: [e], timeout: 45)
        sleep(20)   // let a few hundred metres and a split pace accrue

        // Marketing captures only (MILEPOST_LONG_RUN=1): keep going past the
        // first split so the recorder, detail and totals show a real run, and
        // grab the map with the route drawn in. ~9 minutes at the simulated jog.
        if ProcessInfo.processInfo.environment["MILEPOST_LONG_RUN"] == "1" {
            let target = 1.2
            let deadline = Date().addingTimeInterval(14 * 60)
            while Date() < deadline {
                if let v = Double(distance.label), v >= target { break }
                sleep(5)
            }
            tap("live.collapse")
            XCTAssertTrue(app.buttons["record.expand"].waitForExistence(timeout: 6))
            sleep(3)
            snap("map-route")
            tap("record.expand")
            XCTAssertTrue(app.staticTexts["live.time"].waitForExistence(timeout: 6))
            sleep(1)
        }
        snap("route-recording")

        // The Live Activity must carry the ground actually covered, and the
        // compact island is where that has to show: it is what you see
        // without touching the phone. The run is still moving, so assert it
        // is non-zero rather than matching the app's label exactly.
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let covered = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label MATCHES %@", "^[0-9]+\\.[0-9]+ mi$")).firstMatch
        XCTAssertTrue(covered.waitForExistence(timeout: 15),
                      "no distance in the compact Dynamic Island while the run is moving")
        let miles = Double(covered.label.prefix(while: { $0 != " " })) ?? 0
        XCTAssertGreaterThan(miles, 0, "the island is stuck at 0.00 mi during a moving run")

        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.037))
            .press(forDuration: 1.2)
        // BEGINSWITH "Mile " (not a hardcoded "Mile 1"): MILEPOST_LONG_RUN
        // deliberately drives distance past 1.0 mi to show a split, at which
        // point RunRecorder.swift bumps splitIndex to 2 (Mile 2 in
        // progress). A literal "Mile 1" here always failed on that path.
        XCTAssertTrue(springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Mile ")).firstMatch
            .waitForExistence(timeout: 8), "no mile in progress on the expanded island")
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()
        app.activate()
        XCTAssertTrue(app.buttons["live.pause"].waitForExistence(timeout: 8))

        tap("live.pause")
        tap("live.finish")

        let title = app.textFields["save.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8), "save sheet never appeared")
        XCTAssertTrue(title.value as? String != nil)
        snap("route-save")
        tap("save.save")

        XCTAssertTrue(app.staticTexts["celebrate.title"].waitForExistence(timeout: 8), "no congratulations splash after save")
        XCTAssertTrue(app.staticTexts["celebrate.distance"].exists)
        snap("route-celebrate")
        tap("celebrate.done")
        XCTAssertTrue(app.staticTexts["celebrate.title"].waitForNonExistence(timeout: 4), "the splash did not close")

        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["record.distance"].label, "0.00", "map card resets after save")

        tap("tab.block")
        let row = app.staticTexts["block.rowTitle"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertTrue(row.label.hasSuffix("Run"))
        snap("activities-list")
        row.tap()
        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Distance"].exists)
        XCTAssertTrue(app.staticTexts["Splits (mi)"].exists)
        snap("route-detail")

        // Marketing captures only: the You tab with a real run behind its
        // totals. Off the regression path so a flaky pop cannot fail the suite.
        if let dir = ProcessInfo.processInfo.environment["MILEPOST_SHOTS"], !dir.isEmpty {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            tap("tab.you")
            XCTAssertTrue(app.staticTexts["This week"].waitForExistence(timeout: 6))
            sleep(1)
            snap("you-totals")
            tap("tab.block")
            XCTAssertTrue(row.waitForExistence(timeout: 8))
            row.tap()
            XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 8))
        }

        tap("detail.menu")
        tap("detail.delete")
        let confirm = app.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 4))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["No activities yet"].waitForExistence(timeout: 8))
    }
}

import XCTest

/// A ride recorded off a moving simulator at about 18 mph. run_tests.sh
/// starts the faster route before this class runs. What matters here is that
/// bike speeds are actually tracked: at 18 mph a run's plausibility bounds
/// would have shown "-:--" for the whole ride.
final class MilepostRideUITests: XCTestCase {

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

    func testARideTracksDistanceAndSpeedAndSaves() {
        tap("record.sport")
        tap("sport.bike")
        XCTAssertEqual(app.buttons["record.sport"].label, "Sport, Ride")

        tap("record.start")
        allowLocation()
        if !app.buttons["live.pause"].waitForExistence(timeout: 4), app.buttons["record.start"].exists {
            tap("record.start")
        }
        XCTAssertTrue(app.buttons["live.pause"].waitForExistence(timeout: 8))

        let distance = app.staticTexts["live.distance"]
        let moved = NSPredicate(format: "label != '0.00'")
        wait(for: [expectation(for: moved, evaluatedWith: distance)], timeout: 45)

        // Far enough for a split speed to settle.
        let speed = app.staticTexts["live.pace"]
        let priced = NSPredicate(format: "label != '-.-'")
        wait(for: [expectation(for: priced, evaluatedWith: speed)], timeout: 60)

        let mph = Double(speed.label) ?? 0
        XCTAssertGreaterThan(mph, 5, "a ride at 18 mph should not read as \(speed.label) mph")
        XCTAssertLessThan(mph, 45, "\(speed.label) mph is not a bike")
        XCTAssertTrue(app.staticTexts["Split avg. speed (mph)"].exists)
        snap("ride-recording")

        tap("live.pause")
        tap("live.finish")

        let title = app.textFields["save.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8), "save sheet never appeared")
        XCTAssertTrue((title.value as? String ?? "").hasSuffix("Ride"), "the ride was titled a run")
        XCTAssertTrue(app.staticTexts["Avg. speed"].exists, "the save sheet still says pace")
        snap("ride-save")
        tap("save.save")

        XCTAssertTrue(app.staticTexts["celebrate.title"].waitForExistence(timeout: 8), "no congratulations splash after save")
        XCTAssertTrue(app.staticTexts["celebrate.distance"].exists)
        snap("ride-celebrate")
        tap("celebrate.done")
        XCTAssertTrue(app.staticTexts["celebrate.title"].waitForNonExistence(timeout: 4), "the splash did not close")

        tap("tab.block")
        let row = app.staticTexts["block.rowTitle"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertTrue(row.label.hasSuffix("Ride"))
        row.tap()
        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Avg. speed"].exists, "the saved ride reads in pace")
        XCTAssertTrue(app.navigationBars["Ride"].exists, "the detail screen is still titled Run")
        snap("ride-detail")

        tap("detail.menu")
        tap("detail.delete")
        let confirm = app.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 4))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["No activities yet"].waitForExistence(timeout: 8))
    }
}

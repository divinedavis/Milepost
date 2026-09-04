import XCTest

/// Needs the simulator to be moving: run_tests.sh starts a simctl location
/// route before this class runs. Start → distance climbs → Pause → Finish →
/// Save → the run shows up in Activities with a route map.
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

    func testMovingRunSavesAndAppearsInActivities() {
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
        snap("route-recording")

        tap("live.pause")
        tap("live.finish")

        let title = app.textFields["save.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8), "save sheet never appeared")
        XCTAssertTrue(title.value as? String != nil)
        snap("route-save")
        tap("save.save")

        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts["record.distance"].label, "0.00", "map card resets after save")

        tap("tab.activities")
        let row = app.staticTexts["activities.rowTitle"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertTrue(row.label.hasSuffix("Run"))
        row.tap()
        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Distance"].exists)
        XCTAssertTrue(app.staticTexts["Splits (mi)"].exists)
        snap("route-detail")

        tap("detail.menu")
        tap("detail.delete")
        let confirm = app.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 4))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["No runs yet"].waitForExistence(timeout: 8))
    }
}

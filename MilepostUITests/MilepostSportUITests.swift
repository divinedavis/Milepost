import XCTest

/// Choosing a sport from the Record tab, and what each one changes.
/// Static location (run_tests.sh), so every run here ends in "No Movement
/// Detected" — what is under test is the selection and the labelling, not
/// distance, which the moving suite and the unit tests cover.
final class MilepostSportUITests: XCTestCase {

    private var app: XCUIApplication!

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

    private func choose(_ sport: String) {
        tap("record.sport")
        XCTAssertTrue(app.buttons["sport.\(sport)"].waitForExistence(timeout: 6), "picker never opened")
        tap("sport.\(sport)")
    }

    /// The Start button sits on the screen's centre line for every sport.
    /// It used to drift: the three columns were sized by their own labels, so
    /// "Stroller Run" — wider than the circle above it and wider than
    /// "History" — grew the left column and pushed Start right.
    func testStartStaysCentredForEverySport() {
        let screen = app.windows.firstMatch.frame
        for sport in ["run", "strollerRun", "walk", "bike"] {
            choose(sport)
            let start = app.buttons["record.start"]
            XCTAssertTrue(start.waitForExistence(timeout: 6), "no Start button after choosing \(sport)")
            let offset = start.frame.midX - screen.midX
            XCTAssertLessThan(abs(offset), 1.5, "Start is \(offset) pt off centre with \(sport) selected")
        }
        snap("record-start-centred")
    }

    /// Every sport is reachable and the chip follows the choice.
    func testPickerOffersEverySportAndTheChipFollows() {
        tap("record.sport")
        XCTAssertTrue(app.buttons["sport.run"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["sport.walk"].exists)
        XCTAssertTrue(app.buttons["sport.bike"].exists)
        XCTAssertTrue(app.buttons["sport.strollerRun"].isHittable)
        XCTAssertTrue(app.buttons["sport.bike"].isHittable)
        snap("sport-picker")

        tap("sport.walk")
        XCTAssertTrue(app.buttons["record.sport"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.buttons["record.sport"].label, "Sport, Walk")

        choose("bike")
        XCTAssertEqual(app.buttons["record.sport"].label, "Sport, Ride")

        // Cancelling leaves the choice alone.
        tap("record.sport")
        tap("sport.cancel")
        XCTAssertEqual(app.buttons["record.sport"].label, "Sport, Ride")
    }

    func testStrollerRunKeepsPaceAndTheChoiceSticks() {
        choose("strollerRun")
        XCTAssertEqual(app.buttons["record.sport"].label, "Sport, Stroller Run")
        // Pace vs speed per sport is pinned in SportTests; the Record tab
        // shows no stats until a workout starts (2026-10-22).
        XCTAssertFalse(app.staticTexts["record.pace"].exists)
        snap("stroller-run-selected")
        tap("tab.you")
        tap("tab.record")
        XCTAssertEqual(app.buttons["record.sport"].label, "Sport, Stroller Run")
    }

    /// A ride reads in miles per hour. Minutes per mile is meaningless at
    /// bike speeds, so the label and the placeholder both have to change.
    func testARideIsMeasuredInSpeedNotPace() {
        choose("bike")
        XCTAssertFalse(app.staticTexts["record.pace"].exists, "no stats card before Start")

        tap("record.start")
        allowLocation()
        if !app.buttons["live.pause"].waitForExistence(timeout: 4), app.buttons["record.start"].exists {
            tap("record.start")
        }
        XCTAssertTrue(app.buttons["live.pause"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Split avg. speed (mph)"].waitForExistence(timeout: 6),
                      "the recorder still offers pace for a ride")
        // Collapsed, the map card is back for the workout, in speed.
        tap("live.collapse")
        XCTAssertTrue(app.staticTexts["Avg. speed (mph)"].waitForExistence(timeout: 6),
                      "the map card still offers pace for a ride")
        XCTAssertEqual(app.staticTexts["record.pace"].label, "-.-")
        tap("record.expand")
        snap("live-ride")

        // Finish with no movement: the sheet and alert speak of a ride.
        tap("live.pause")
        tap("live.finish")
        XCTAssertTrue(app.alerts["No Movement Detected"].waitForExistence(timeout: 6))
        app.alerts.buttons["Discard"].tap()
        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.buttons["record.sport"].label, "Sport, Ride", "the choice survives a discarded ride")
    }

    /// A walk keeps pace, and the sport sticks across the tab bar.
    func testAWalkKeepsPaceAndTheChoiceSticks() {
        choose("walk")
        XCTAssertEqual(app.buttons["record.sport"].label, "Sport, Walk")

        tap("tab.you")
        XCTAssertTrue(app.buttons["you.map"].waitForExistence(timeout: 6))
        tap("tab.record")
        XCTAssertEqual(app.buttons["record.sport"].label, "Sport, Walk")
    }
}

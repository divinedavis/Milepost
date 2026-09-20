import XCTest

/// The cold-launch splash. Every other class launches with the splash off
/// (`-uitest` alone) so it costs them nothing; this one opts in.
final class MilepostSplashUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSplashPlaysThenHandsOffToRecord() {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest", "-uitest-splash"]
        app.launch()

        let splash = app.otherElements["splash"]
        XCTAssertTrue(splash.waitForExistence(timeout: 3), "splash never appeared on a cold launch")
        XCTAssertEqual(splash.label, "Milepost")

        // It plays for ~1.8 s and must get out of the way on its own.
        XCTAssertTrue(splash.waitForNonExistence(timeout: 6), "splash never finished")
        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 6), "Record tab not reachable after the splash")
        XCTAssertFalse(app.otherElements["splash"].exists, "splash came back after the hand-off")
    }

    func testPlainTestLaunchSkipsTheSplash() {
        let app = XCUIApplication()
        app.launchArguments += ["-uitest"]
        app.launch()
        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.otherElements["splash"].exists, "-uitest alone should never show the splash")
    }
}

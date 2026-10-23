import XCTest

/// Holiday themes (2026-10-22). `-HOLIDAY <id>` dresses the app for one day
/// whatever the date; plain `-uitest` always sees the everyday app.
final class MilepostHolidayUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testAForcedHolidayDressesTheRecordScreen() {
        app.launchArguments = ["-uitest", "-HOLIDAY", "thanksgiving"]
        app.launch()
        let start = app.buttons["record.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertEqual(start.value as? String, "Thanksgiving theme")
        // The tab bar still works with the holiday pill.
        app.buttons["tab.block"].tap()
        XCTAssertTrue(app.buttons["tab.block"].isSelected)
        app.buttons["tab.record"].tap()
        XCTAssertTrue(start.waitForExistence(timeout: 6))
    }

    func testTheEverydayAppHasNoTheme() {
        app.launchArguments = ["-uitest"]
        app.launch()
        let start = app.buttons["record.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertEqual(start.value as? String ?? "", "", "UI tests must not pick up today's holiday")
    }

    func testTheSplashNamesTheHoliday() {
        app.launchArguments = ["-uitest", "-uitest-splash", "-HOLIDAY", "global-running-day"]
        app.launch()
        let splash = app.otherElements["splash"]
        XCTAssertTrue(splash.waitForExistence(timeout: 6))
        XCTAssertEqual(splash.label, "Milepost, Global Running Day")
    }

    func testHolidayIconsSwitchIsOnInSettings() {
        app.launchArguments = ["-uitest"]
        app.launch()
        app.buttons["tab.you"].tap()
        XCTAssertTrue(app.buttons["you.map"].waitForExistence(timeout: 8))
        let row = app.buttons["you.rowSettings"]
        for _ in 0..<8 where !(row.exists && row.isHittable) { app.swipeUp(velocity: .slow) }
        row.tap()
        let toggle = app.switches["you.holidayIcons"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 6))
        XCTAssertEqual(toggle.value as? String, "1", "holiday icons are on by default, like Marracat's")
    }
}

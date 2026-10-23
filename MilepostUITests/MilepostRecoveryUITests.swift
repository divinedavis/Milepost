import XCTest

/// A walk the app died halfway through comes back saved (2026-10-22), and
/// the Daily steps card on You reads Health's day totals.
final class MilepostRecoveryUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    func testAnInterruptedWalkIsSavedAndAnnounced() {
        app.launchArguments = ["-uitest", "-uitest-seed-checkpoint"]
        app.launch()

        let banner = app.otherElements["record.recovered"]
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "the rescued-walk card never appeared")
        let view = app.buttons["record.recoveredView"]
        XCTAssertTrue(view.exists)
        view.tap()

        let row = app.staticTexts.matching(identifier: "block.rowTitle").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 6), "the walk is not in Block")
        XCTAssertTrue(row.label.contains("Walk"), row.label)
        XCTAssertEqual(app.staticTexts.matching(identifier: "block.rowTitle").count, 1)

        // Shown once: back on Record the card is gone.
        app.buttons["tab.record"].tap()
        XCTAssertFalse(app.otherElements["record.recovered"].waitForExistence(timeout: 2))
    }

    func testDismissingTheCardKeepsTheWalk() {
        app.launchArguments = ["-uitest", "-uitest-seed-checkpoint"]
        app.launch()
        let dismiss = app.buttons["record.recoveredDismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 10))
        dismiss.tap()
        XCTAssertFalse(app.otherElements["record.recovered"].waitForExistence(timeout: 2))

        app.buttons["tab.block"].tap()
        XCTAssertTrue(app.staticTexts.matching(identifier: "block.rowTitle").firstMatch.waitForExistence(timeout: 6))
    }

    /// A normal launch has nothing to recover and shows no card.
    func testAPlainLaunchShowsNoCard() {
        app.launchArguments = ["-uitest"]
        app.launch()
        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.otherElements["record.recovered"].exists)
    }

    func testDailyStepsCardShowsTodayAndTheWeek() {
        app.launchArguments = ["-uitest", "-uitest-daily-demo"]
        app.launch()
        app.buttons["tab.you"].tap()

        let today = app.otherElements["you.dailyToday"].exists
            ? app.otherElements["you.dailyToday"]
            : app.descendants(matching: .any)["you.dailyToday"]
        XCTAssertTrue(today.waitForExistence(timeout: 8), "the Daily steps card never appeared")
        XCTAssertTrue(today.label.contains("6,412"), today.label)
        XCTAssertTrue(today.label.contains("steps today"), today.label)
        XCTAssertGreaterThanOrEqual(app.descendants(matching: .any).matching(identifier: "you.dailyDay").count, 3)

        // The switch that controls it is in Apple Health, and it is on.
        let toggle = app.switches["you.healthDaily"]
        for _ in 0..<6 where !(toggle.exists && toggle.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(toggle.exists, "Daily steps switch missing from Apple Health")
        XCTAssertEqual(toggle.value as? String, "1")
    }
}

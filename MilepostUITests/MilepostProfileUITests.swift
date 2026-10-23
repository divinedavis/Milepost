import XCTest

/// Profile (2026-10-22, after Airbnb's): the header card's numbers, the map
/// of every route, the tiles, and the in-app friend request notification.
final class MilepostProfileUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ extra: [String]) {
        app.launchArguments = ["-uitest"] + extra
        app.launch()
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func testHeaderCountsAndTheMapDrawsEveryRoute() {
        // Three past walks (HeatmapPreviewData).
        launch(["-uitest-seed-heatmap"])
        app.buttons["tab.you"].tap()
        let activities = element("you.statActivities")
        XCTAssertTrue(activities.waitForExistence(timeout: 8))
        XCTAssertTrue(activities.label.contains("3"), activities.label)
        XCTAssertTrue(element("you.statTenure").label.contains("on Milepost"), element("you.statTenure").label)

        app.buttons["you.map"].tap()
        let count = app.staticTexts["routes.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 8), "the map never opened")
        XCTAssertEqual(count.label, "3 activities")

        app.buttons["routes.filter.run"].tap()
        XCTAssertEqual(count.label, "0 activities", "the seeded activities are walks")
        app.buttons["routes.filter.walk"].tap()
        XCTAssertEqual(count.label, "3 activities")
        app.buttons["routes.filter.all"].tap()
        XCTAssertEqual(count.label, "3 activities")

        app.buttons["routes.close"].tap()
        XCTAssertTrue(app.buttons["you.map"].waitForExistence(timeout: 6))
    }

    func testAnEmptyMapSaysWhatWillAppear() {
        launch([])
        app.buttons["tab.you"].tap()
        XCTAssertTrue(app.buttons["you.map"].waitForExistence(timeout: 8))
        app.buttons["you.map"].tap()
        let count = app.staticTexts["routes.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 8))
        XCTAssertTrue(count.label.contains("first activity"), count.label)
        app.buttons["routes.close"].tap()
    }

    func testTilesOpenActivitiesAndFriends() {
        launch(["-uitest-social-demo"])
        app.buttons["tab.you"].tap()
        XCTAssertTrue(app.buttons["you.tileActivities"].waitForExistence(timeout: 8))
        app.buttons["you.tileActivities"].tap()
        XCTAssertTrue(app.buttons["tab.block"].isSelected, "Activities goes to Block")

        app.buttons["tab.you"].tap()
        app.buttons["you.tileFriends"].tap()
        XCTAssertTrue(app.textFields["friends.search"].waitForExistence(timeout: 8), "Friends tile opens Friends")
    }

    /// A waiting request shows up three ways: the banner on arrival, a dot on
    /// the Profile tab, and the bell. View goes straight to the request.
    func testAFriendRequestIsAnnouncedInTheApp() {
        launch(["-uitest-social-demo", "-uitest-request-banner"])
        let banner = element("request.banner")
        XCTAssertTrue(banner.waitForExistence(timeout: 12), "no banner for the waiting request")
        XCTAssertTrue(app.staticTexts["Sam sent you a friend request"].exists)
        XCTAssertEqual(app.buttons["tab.you"].value as? String, "1 friend request")

        app.buttons["request.view"].tap()
        let accept = app.buttons["friends.accept.sam_walks"]
        XCTAssertTrue(accept.waitForExistence(timeout: 8), "View did not open the request")
        accept.tap()
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: accept)], timeout: 6)
        XCTAssertEqual(app.buttons["tab.you"].value as? String ?? "", "", "the dot clears once answered")
    }

    func testTheBellShowsAndOpensRequests() {
        launch(["-uitest-social-demo"])
        app.buttons["tab.you"].tap()
        let bell = app.buttons["you.notifications"]
        XCTAssertTrue(bell.waitForExistence(timeout: 8))
        // Connections load with the Friends data; give them a moment.
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'friend request'"), object: bell)], timeout: 8)
        bell.tap()
        XCTAssertTrue(app.buttons["friends.accept.sam_walks"].waitForExistence(timeout: 8))
        XCTAssertFalse(element("request.banner").exists, "UI tests only show the banner when asked")
    }
}

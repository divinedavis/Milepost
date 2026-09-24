import XCTest

/// The Block tab's Friends feed, the Friends screen and the account section
/// on You. A runner-launched app cannot keep a real Supabase session (no
/// keychain) or drive the Sign in with Apple sheet, so signed-in flows run
/// against the in-memory demo backend (`-uitest-social-demo`, Debug only).
/// The real backend is covered by scripts/e2e_backend.py.
final class MilepostFriendsUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(demo: Bool) {
        app.launchArguments = ["-uitest"] + (demo ? ["-uitest-social-demo"] : [])
        app.launch()
    }

    private func tap(_ id: String, timeout: TimeInterval = 6) {
        let el = app.buttons[id]
        XCTAssertTrue(el.waitForExistence(timeout: timeout), "\(id) never appeared")
        el.tap()
    }

    /// Matches by identifier whatever element type SwiftUI chose.
    /// Swipes up until `id` is in the accessibility tree, or gives up.
    private func scrollToElement(_ id: String, attempts: Int = 6) {
        for _ in 0..<attempts {
            if element(id).exists { return }
            app.swipeUp()
        }
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// A Text that carries an accessibility identifier is not found by its
    /// label through `staticTexts["…"]`, so match the label explicitly.
    private func text(_ label: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func waitGone(_ el: XCUIElement, timeout: TimeInterval = 6) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: el)
        return XCTWaiter.wait(for: [gone], timeout: timeout) == .completed
    }

    /// tap-then-typeText is unreliable: wait for the keyboard, re-tap once.
    private func type(_ text: String, into field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { field.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 3), "keyboard never came up")
        field.typeText(text)
    }

    /// A plain `.tap()` on the segment reported success without selecting it
    /// (both tests sat on Mine). Confirm via isSelected, coordinate-tap if not.
    private func selectSegment(_ label: String) {
        let segment = app.segmentedControls["block.feed"].buttons[label]
        XCTAssertTrue(segment.waitForExistence(timeout: 6))
        for _ in 0..<3 where !segment.isSelected {
            segment.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let selected = expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: segment)
            _ = XCTWaiter.wait(for: [selected], timeout: 2)
        }
        XCTAssertTrue(segment.isSelected, "\(label) segment never selected")
    }

    private func openFriendsFeed() {
        tap("tab.block")
        selectSegment("Friends")
    }

    func testSignedOutFriendsFeedOffersAppleSignIn() {
        launch(demo: false)
        tap("tab.block")
        XCTAssertTrue(app.staticTexts["No activities yet"].waitForExistence(timeout: 6), "Mine is the default")
        openFriendsFeed()
        XCTAssertTrue(app.staticTexts["Run with friends"].waitForExistence(timeout: 6))
        XCTAssertTrue(element("signin.apple").waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["block.friends"].exists, "no add-friends button before an account exists")

        selectSegment("Mine")
        XCTAssertTrue(app.staticTexts["No activities yet"].waitForExistence(timeout: 4))
    }

    func testFriendFeedRequestsAndSearch() {
        launch(demo: true)
        openFriendsFeed()
        XCTAssertTrue(text("Lunch Loop").waitForExistence(timeout: 8), "a friend's activity is in the feed")
        XCTAssertTrue(text("Jamie").exists)
        XCTAssertFalse(text("Evening Walk").exists, "a pending request shows nothing")

        tap("block.friends")
        tap("friends.accept.sam_walks")
        XCTAssertTrue(waitGone(app.buttons["friends.accept.sam_walks"]), "accepted request leaves the list")
        XCTAssertTrue(element("friends.friend.sam_walks").waitForExistence(timeout: 6))

        type("jor", into: app.textFields["friends.search"])
        tap("friends.add.jordan_rides")
        let status = element("friends.status.jordan_rides")
        XCTAssertTrue(status.waitForExistence(timeout: 6))
        XCTAssertEqual(status.label, "Requested")
        // Sent is the last section: put the keyboard away and bring it up,
        // since offscreen List cells are not in the accessibility tree.
        app.textFields["friends.search"].typeText("\n")
        app.swipeUp()
        XCTAssertTrue(element("friends.cancel.jordan_rides").waitForExistence(timeout: 6), "shows under Sent")

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(text("Evening Walk").waitForExistence(timeout: 8), "the new friend's activity arrives")
    }

    func testAccountSectionOnYou() {
        launch(demo: true)
        tap("tab.you")
        // The Account section sits below the fold, and how far below moves
        // whenever a setting is added above it (Apple Health did). Offscreen
        // List cells are not in the accessibility tree, so scroll until it is
        // there rather than guessing a number of swipes.
        scrollToElement("you.username")
        XCTAssertTrue(element("you.username").waitForExistence(timeout: 6))
        XCTAssertTrue(element("you.username").label.contains("@you_demo"), element("you.username").label)
        XCTAssertTrue(element("you.share").exists)
        // The rest of the section can still be below the fold (the Oura row
        // pushed it there), so scroll again instead of assuming it is on screen.
        scrollToElement("you.deleteAccount")
        XCTAssertTrue(element("you.deleteAccount").exists, "App Store 5.1.1(v)")

        let signOut = element("you.signOut")
        XCTAssertTrue(signOut.exists)
        signOut.tap()
        XCTAssertTrue(element("signin.apple").waitForExistence(timeout: 6))
        XCTAssertFalse(element("you.username").exists)
    }
}

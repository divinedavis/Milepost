import XCTest

/// The neutral age question a brand-new friends account answers (COPPA,
/// 2026-11-07). XCUITest cannot drive Apple's sign-in sheet, so
/// `-uitest-age-new-account` starts the demo backend in the state a first
/// Sign in with Apple leaves: a new account, held for the answer. The
/// sign-in decision itself (new vs existing, blocked phone) is unit-tested
/// in AgeGateSwiftTests.
final class MilepostAgeGateUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(_ args: [String]) {
        app.launchArguments = ["-uitest"] + args
        app.launch()
    }

    private func launchNewAccount() {
        launch(["-uitest-social-demo", "-uitest-age-new-account"])
        XCTAssertTrue(app.staticTexts["ageGate.title"].waitForExistence(timeout: 15), "the age question never appeared")
    }

    private var monthWheel: XCUIElement { app.pickerWheels.element(boundBy: 0) }
    private var yearWheel: XCUIElement { app.pickerWheels.element(boundBy: 1) }
    private var thisYear: String { String(Calendar.current.component(.year, from: .now)) }

    private func waitGone(_ el: XCUIElement, timeout: TimeInterval = 6) -> Bool {
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: el)
        return XCTWaiter.wait(for: [gone], timeout: timeout) == .completed
    }

    private func element(_ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// Mine/Friends needs a coordinate tap on iOS 26 (see MilepostFriendsUITests).
    private func openFriendsFeed() {
        app.buttons["tab.block"].tap()
        let segment = app.segmentedControls["block.feed"].buttons["Friends"]
        XCTAssertTrue(segment.waitForExistence(timeout: 6))
        for _ in 0..<3 where !segment.isSelected {
            segment.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let selected = expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: segment)
            _ = XCTWaiter.wait(for: [selected], timeout: 2)
        }
        XCTAssertTrue(segment.isSelected, "Friends segment never selected")
    }

    func testNewAccountAsksAgeWithNothingPreselected() {
        launchNewAccount()
        XCTAssertEqual(monthWheel.value as? String, "Month", "a month was pre-selected")
        XCTAssertEqual(yearWheel.value as? String, "Year", "a year was pre-selected")
        XCTAssertFalse(app.buttons["ageGate.continue"].isEnabled, "Continue must wait for both answers")
        monthWheel.adjust(toPickerWheelValue: "March")
        XCTAssertFalse(app.buttons["ageGate.continue"].isEnabled, "Continue must wait for the year too")
        // The copy names no age.
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '13'")).firstMatch.exists)
    }

    func testThirteenPlusContinuesIntoFriends() {
        launchNewAccount()
        monthWheel.adjust(toPickerWheelValue: "March")
        yearWheel.adjust(toPickerWheelValue: "2000")
        app.buttons["ageGate.continue"].tap()
        XCTAssertTrue(waitGone(app.staticTexts["ageGate.title"]), "the question stayed up after a 13+ answer")
        openFriendsFeed()
        XCTAssertFalse(element("signin.apple").waitForExistence(timeout: 3), "a 13+ account should be signed in")
    }

    func testUnderThirteenIsBlockedAndRemembered() {
        launchNewAccount()
        monthWheel.adjust(toPickerWheelValue: "January")
        yearWheel.adjust(toPickerWheelValue: thisYear)
        app.buttons["ageGate.continue"].tap()
        XCTAssertTrue(app.staticTexts["ageBlocked.title"].waitForExistence(timeout: 6), "no friendly block after an under-13 answer")
        app.buttons["ageBlocked.done"].tap()
        XCTAssertTrue(waitGone(app.staticTexts["ageBlocked.title"]))
        // The new account was deleted: Friends is signed out, and says why
        // nothing new can be made here.
        openFriendsFeed()
        XCTAssertTrue(element("signin.apple").waitForExistence(timeout: 6), "the under-13 account was not discarded")
        XCTAssertTrue(element("ageBlocked.note").exists)

        // A relaunch (the Keychain outliving a reinstall) keeps the block.
        app.terminate()
        launch(["-uitest-social-demo", "-uitest-signed-out", "-uitest-keep-agegate"])
        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 15))
        openFriendsFeed()
        XCTAssertTrue(element("signin.apple").waitForExistence(timeout: 6))
        XCTAssertTrue(element("ageBlocked.note").exists, "the block did not survive a relaunch")
    }

    func testCancelDiscardsTheNewAccountWithoutBlocking() {
        launchNewAccount()
        app.buttons["ageGate.cancel"].tap()
        XCTAssertTrue(waitGone(app.staticTexts["ageGate.title"]), "Cancel left the question up")
        openFriendsFeed()
        XCTAssertTrue(element("signin.apple").waitForExistence(timeout: 6), "Cancel should leave the phone signed out")
        XCTAssertFalse(element("ageBlocked.note").exists, "Cancel must not block the phone")
    }

    func testAPhoneThatNeverSawTheQuestionIsNotBlocked() {
        launch(["-uitest-social-demo", "-uitest-signed-out"])
        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["ageGate.title"].exists, "existing state must not be asked")
        openFriendsFeed()
        XCTAssertTrue(element("signin.apple").waitForExistence(timeout: 6))
        XCTAssertFalse(element("ageBlocked.note").exists)
    }
}

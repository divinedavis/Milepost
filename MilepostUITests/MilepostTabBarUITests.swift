import XCTest

/// The floating tab bar (2026-10-22) sits over the screens. Scrolled to the
/// bottom, every screen's last row has to end above it: on 1.6 build 34 the
/// bar covered Profile's Privacy row and a run's splits (owner, 2026-10-23).
final class MilepostTabBarUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uitest", "-uitest-seed-heatmap"]
        app.launch()
    }

    /// Top of the capsule: the buttons sit 5pt inside it.
    private var barTop: CGFloat { app.buttons["tab.record"].frame.minY - 5 }

    /// The lowest on-screen piece of the screen's scrolling content.
    private func lowestContent(in scroll: XCUIElement) -> (label: String, maxY: CGFloat) {
        let screen = app.windows.firstMatch.frame
        var lowest = (label: "", maxY: CGFloat(0))
        // What a person reads or taps; blank cell backgrounds don't count.
        let types: [XCUIElement.ElementType] = [.staticText, .button, .switch, .link, .image]
        let items = types.flatMap { scroll.descendants(matching: $0).allElementsBoundByIndex }
        for item in items where !item.label.isEmpty {
            let f = item.frame
            guard !f.isEmpty, f.minY < screen.maxY, f.height < screen.height / 2 else { continue }
            if f.maxY > lowest.maxY { lowest = ("\(item.identifier) \(item.label)", f.maxY) }
        }
        return lowest
    }

    private func snap(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["MILEPOST_SHOTS"], !dir.isEmpty else { return }
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func assertClearsTheBar(_ scroll: XCUIElement, _ screen: String) {
        XCTAssertTrue(scroll.waitForExistence(timeout: 8), "\(screen) never appeared")
        // Swipe until the bottom stops moving: a list still decelerating
        // reads lower than where it comes to rest.
        var lowest = lowestContent(in: scroll)
        for _ in 0..<8 {
            scroll.swipeUp()
            Thread.sleep(forTimeInterval: 1)
            let next = lowestContent(in: scroll)
            if next == lowest { break }
            lowest = next
        }
        snap("tabbar-\(screen)")
        XCTAssertLessThanOrEqual(lowest.maxY, barTop + 1,
                                 "\(screen): '\(lowest.label)' ends under the tab bar")
    }

    func testProfileEndsAboveTheBar() {
        app.buttons["tab.you"].tap()
        assertClearsTheBar(app.collectionViews.firstMatch, "Profile")
    }

    func testSettingsEndsAboveTheBar() {
        app.buttons["tab.you"].tap()
        let row = app.buttons["you.rowSettings"]
        for _ in 0..<5 where !row.isHittable { app.collectionViews.firstMatch.swipeUp() }
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["you.units"].waitForExistence(timeout: 6))
        assertClearsTheBar(app.collectionViews.firstMatch, "Settings")
    }

    func testActivitiesAndARunEndAboveTheBar() {
        app.buttons["tab.block"].tap()
        let list = app.collectionViews.firstMatch
        assertClearsTheBar(list, "Activities")

        let row = app.staticTexts["block.rowTitle"].firstMatch
        for _ in 0..<5 where !row.isHittable { list.swipeDown() }
        row.tap()
        XCTAssertTrue(app.staticTexts["detail.title"].waitForExistence(timeout: 8))
        assertClearsTheBar(app.scrollViews.firstMatch, "A run")
    }
}

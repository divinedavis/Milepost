import XCTest

/// Past activities on the Record map. The polylines themselves are not in
/// the accessibility tree, so the window control reports how many
/// activities it is drawing and the test reads that.
final class MilepostHeatmapUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-uitest", "-uitest-seed-heatmap"]
        app.launch()
    }

    private func snap(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["MILEPOST_SHOTS"], !dir.isEmpty else { return }
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func value(_ el: XCUIElement) -> String { (el.value as? String) ?? "" }

    func testThirtyDaysByDefaultAndAWiderWindowShowsMore() {
        let control = app.buttons["record.heatWindow"]
        XCTAssertTrue(control.waitForExistence(timeout: 10), "no past-activities control on the map")
        XCTAssertTrue(control.label.contains("30 days"), "default window is \(control.label)")
        // Two seeded walks are this month, one is 60 days old.
        XCTAssertEqual(value(control), "2 activities")
        sleep(2) // let the tiles and the polylines draw
        snap("heatmap-30-days")

        control.tap()
        let all = app.buttons["All time"]
        XCTAssertTrue(all.waitForExistence(timeout: 6), "window menu never opened")
        all.tap()
        XCTAssertTrue(control.label.contains("All time"))
        XCTAssertEqual(value(control), "3 activities")

        control.tap()
        let off = app.buttons["Off"]
        XCTAssertTrue(off.waitForExistence(timeout: 6))
        off.tap()
        XCTAssertEqual(value(control), "0 activities")
    }
}

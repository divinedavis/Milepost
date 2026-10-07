import XCTest

/// Speed and memory on the paths people wait on, added 2026-10-07 with
/// Apple's XCTMetric API. scripts/perf_gate.py fails the ship when a metric
/// is more than 1.5x the median of the last five passing ships
/// (scripts/perf_baseline.json). Simulator numbers catch regressions, not
/// real-world times; those come from MetricKit (Services/MetricsReporter.swift)
/// and the Xcode Organizer (scripts/organizer_report.py).
final class PerformanceTests: XCTestCase {
    private let args = ["-uitest"]

    /// Cold launch to the first frame someone can touch.
    func testLaunch() {
        let opts = XCTMeasureOptions(); opts.iterationCount = 5
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)], options: opts) {
            let app = XCUIApplication(); app.launchArguments = args
            app.launch()
        }
    }

    /// Launch until Start is on screen over the map: what people open it for.
    func testLaunchToRecord() {
        let app = XCUIApplication(); app.launchArguments = args + ["-uitest-seed-heatmap"]
        let opts = XCTMeasureOptions(); opts.iterationCount = 5
        measure(metrics: [XCTClockMetric()], options: opts) {
            app.launch()
            XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 30))
            app.terminate()
        }
    }

    /// Flinging the Block list with seeded activities, and the memory the app
    /// holds with the heatmap loaded.
    func testBlockScroll() {
        let app = XCUIApplication(); app.launchArguments = args + ["-uitest-seed-heatmap"]
        app.launch()
        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 30))
        app.buttons["tab.block"].tap()
        sleep(2)
        let opts = XCTMeasureOptions(); opts.iterationCount = 5
        opts.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTOSSignpostMetric.scrollDecelerationMetric, XCTMemoryMetric(application: app)],
                options: opts) {
            app.swipeUp(velocity: .fast)
            stopMeasuring()
            app.swipeDown(velocity: .fast)
        }
    }
}

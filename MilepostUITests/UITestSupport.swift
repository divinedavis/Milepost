import XCTest

extension XCTestCase {
    /// Taps through the location prompt if one is showing. run_tests.sh
    /// grants location to the simulator up front (2026-10-23), so normally
    /// there is none; the old per-class helpers waited 3 s for each of three
    /// labels, 9 s lost every time no prompt came.
    func allowLocation() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        guard springboard.alerts.firstMatch.waitForExistence(timeout: 1.5) else { return }
        for label in ["Allow While Using App", "Allow Once", "Allow"] {
            let b = springboard.buttons[label]
            if b.exists { b.tap(); return }
        }
    }
}

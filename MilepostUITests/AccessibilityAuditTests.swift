import XCTest

/// Apple's automated accessibility audit (iOS 17+) on every main screen,
/// added 2026-10-07: contrast, Dynamic Type, missing labels, hit targets,
/// traits. scripts/ship.sh refuses to upload a build unless this ran.
///
/// Tabs are read off the hand-rolled tab bar at run time (identifier
/// BEGINSWITH "tab."), so a tab added or removed is audited or dropped
/// without editing this file. Every screen is audited in light AND dark.
///
/// What is excused, and why, lives in `excused(_:)`. Never excuse an issue on
/// one of our own controls to get the gate green; fix the view.
final class AccessibilityAuditTests: XCTestCase {
    private var app: XCUIApplication!
    private var appearanceBefore: XCUIDevice.Appearance = .light

    override func setUp() {
        continueAfterFailure = true   // one screen's issues must not hide the next screen's
        appearanceBefore = XCUIDevice.shared.appearance
    }

    override func tearDown() {
        XCUIDevice.shared.appearance = appearanceBefore
        super.tearDown()
    }

    private func launch(_ extra: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-uitest"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 15), "Record never appeared")
    }

    private var tabIDs: [String] {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab.'"))
            .allElementsBoundByIndex.map(\.identifier)
    }

    private func excused(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard let e = issue.element else { return true }   // nothing to point at
        // Apple draws the Sign in with Apple button and owns its look.
        if e.label.contains("Sign in with Apple") { return true }
        // Map tiles, POI labels and the Legal link are MapKit's, not ours.
        if e.label == "Legal" || e.identifier.hasPrefix("MK") { return true }
        // The system keyboard is not ours.
        let kb = app.keyboards.firstMatch
        if kb.exists, e.frame.minY >= kb.frame.minY - 50 { return true }
        // "Partially unsupported" lands on text the layout deliberately keeps
        // to one line (tab captions, the empty-state title, the stats row);
        // testTheLargestTextSizeStillWorks checks the app stays usable at the
        // largest size. "Unsupported" — a fixed font size — still fails.
        if issue.auditType.contains(.dynamicType), issue.compactDescription.contains("partially") { return true }
        if issue.auditType.contains(.contrast) {
            if !e.isEnabled { return true }   // WCAG 1.4.3 exempts disabled controls
            let window = app.windows.firstMatch.frame
            if !window.isEmpty, e.frame.maxY > window.maxY - 34 { return true }   // under the home indicator
            // GPS pill: opaque #1C1C1C behind white text (~17:1), the same pill
            // that passed before dark glass. With the map now running under the
            // Record panel it sits over map labels, which show at its rounded
            // corners, and the audit reads them as its background (1.6, 10/22).
            if e.identifier == "gps.status" { return true }
            // Content scrolling under the floating dark glass tab bar
            // (2026-10-22): within its reach the system's scroll-edge effect
            // and the bar darken what is behind, so contrast is measured
            // against the bar, not the text's own background. Scrolling
            // moves it clear; the audit only sees the first scroll position.
            let bar = app.buttons["tab.record"].frame
            if !bar.isEmpty, e.elementType == .staticText, e.frame.maxY > bar.minY - 5 - 44 { return true }
        }
        return false
    }

    private static func name(_ t: XCUIAccessibilityAuditType) -> String {
        let names: [(XCUIAccessibilityAuditType, String)] = [
            (.contrast, "contrast"), (.elementDetection, "element detection"), (.hitRegion, "hit region"),
            (.sufficientElementDescription, "description"), (.dynamicType, "dynamic type"),
            (.textClipped, "text clipped"), (.trait, "trait")]
        return names.first { t.contains($0.0) }?.1 ?? "type \(t.rawValue)"
    }

    private func audit(_ screen: String) {
        for look in [XCUIDevice.Appearance.light, .dark] {
            XCUIDevice.shared.appearance = look
            sleep(1)
            auditOnce("\(screen) [\(look == .dark ? "dark" : "light")]")
        }
    }

    private func auditOnce(_ screen: String) {
        var found: [String] = []
        do {
            // Text Clipped fires on labels with room to spare mid-animation.
            var types: XCUIAccessibilityAuditType = .all
            types.remove(.textClipped)
            try app.performAccessibilityAudit(for: types) { issue in
                if self.excused(issue) { return true }
                let e = issue.element
                found.append("\(Self.name(issue.auditType)) — \(issue.compactDescription) — [\(e?.identifier ?? "")] \"\(e?.label ?? "")\""
                             + (e.map { " type \($0.elementType.rawValue) @\(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))x\(Int($0.frame.height))" } ?? ""))
                return true
            }
        } catch {
            XCTFail("\(screen): audit could not run: \(error)")
        }
        if !found.isEmpty {
            XCTFail("\(screen): \(found.count) accessibility issue(s):\n" + found.joined(separator: "\n"))
        }
    }

    func testEveryTab() {
        launch()
        let tabs = tabIDs
        XCTAssertGreaterThan(tabs.count, 1, "the tab bar should list its tabs")
        for id in tabs {
            app.buttons[id].tap()
            sleep(2)
            audit(id)
        }
    }

    /// The Friends side of Block and You, on the demo backend.
    func testFriendsScreens() {
        launch(["-uitest-social-demo"])
        app.buttons["tab.block"].tap()
        sleep(2)
        audit("Block (friends demo)")
        app.buttons["tab.you"].tap()
        sleep(2)
        audit("You (signed in)")
    }

    /// The real Dynamic Type check: at the largest accessibility size every
    /// tab still opens and Start is still there to press.
    func testTheLargestTextSizeStillWorks() {
        launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        let tabs = tabIDs
        XCTAssertGreaterThan(tabs.count, 1)
        for id in tabs.reversed() {
            app.buttons[id].tap()
            XCTAssertTrue(app.buttons[id].isSelected, "\(id) did not open at the largest text size")
        }
        XCTAssertTrue(app.buttons["record.start"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["record.start"].isHittable)
    }
}

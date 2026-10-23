import XCTest
@testable import Milepost

/// The Record panel follows the thumb (2026-10-23): how far the options show
/// for a given drag.
final class RecordPanelTests: XCTestCase {
    func testTheOptionsShowAsFarAsTheFingerGoes() {
        XCTAssertEqual(RecordScreen.rubberBand(120, limit: 400), 120)
        XCTAssertEqual(RecordScreen.rubberBand(400, limit: 400), 400)
    }

    func testPushingDownPastShutStopsAtShut() {
        XCTAssertEqual(RecordScreen.rubberBand(-80, limit: 400), 0)
    }

    func testPullingPastOpenGivesAThirdAsMuch() {
        XCTAssertEqual(RecordScreen.rubberBand(490, limit: 400), 430)
    }
}

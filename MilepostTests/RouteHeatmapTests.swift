import CoreLocation
import XCTest
@testable import Milepost

/// The Record map's heatmap: once is light orange, again is darker, and
/// "again" means the same street, not the next one over.
final class RouteHeatmapTests: XCTestCase {

    /// A straight line north from `lat, lon`, a fix every `step` metres.
    private func line(_ lat: Double, _ lon: Double, meters: Double = 400, step: Double = 8,
                      eastOffset: Double = 0) -> [CLLocationCoordinate2D] {
        let dLon = eastOffset / (111_320 * cos(lat * .pi / 180))
        return stride(from: 0.0, through: meters, by: step).map {
            CLLocationCoordinate2D(latitude: lat + $0 / 110_540, longitude: lon + dLon)
        }
    }

    func testOneActivityIsTheLightestOrange() {
        let segments = RouteHeatmap.segments(routes: [line(40.68, -73.97)])
        XCTAssertFalse(segments.isEmpty)
        XCTAssertEqual(Set(segments.map(\.level)), [0])
    }

    func testTheSameStreetTwiceIsDarker() {
        // Second pass wanders 6 m east, as real GPS does.
        let segments = RouteHeatmap.segments(routes: [line(40.68, -73.97),
                                                      line(40.68, -73.97, eastOffset: 6)])
        XCTAssertEqual(Set(segments.map(\.level)), [1])
    }

    func testTheNextStreetOverDoesNotCount() {
        let segments = RouteHeatmap.segments(routes: [line(40.68, -73.97),
                                                      line(40.68, -73.97, eastOffset: 80)])
        XCTAssertEqual(Set(segments.map(\.level)), [0])
    }

    func testOneActivityLoopingTheSameBlockCountsOnce() {
        let out = line(40.68, -73.97)
        let loop = out + out.reversed() + out
        XCTAssertEqual(Set(RouteHeatmap.segments(routes: [loop]).map(\.level)), [0])
    }

    func testOnlyTheSharedStretchDarkens() {
        let long = line(40.68, -73.97, meters: 800)
        let short = line(40.68, -73.97, meters: 300)
        let levels = Set(RouteHeatmap.segments(routes: [long, short]).map(\.level))
        XCTAssertEqual(levels, [0, 1])
    }

    func testDarkerStretchesDrawOnTop() {
        let long = line(40.68, -73.97, meters: 800)
        let short = line(40.68, -73.97, meters: 300)
        let levels = RouteHeatmap.segments(routes: [long, short, short]).map(\.level)
        XCTAssertEqual(levels, levels.sorted())
    }

    func testNoLineIsDrawnAcrossAGap() {
        let a = line(40.68, -73.97, meters: 100)
        let b = line(40.69, -73.97, meters: 100) // ~1 km north
        let segments = RouteHeatmap.segments(routes: [a + b])
        XCTAssertEqual(segments.count, 2)
        for s in segments {
            for (p, q) in zip(s.coordinates, s.coordinates.dropFirst()) {
                XCTAssertLessThan(RouteHeatmap.distance(p, q), RouteHeatmap.gapMeters)
            }
        }
    }

    func testPassesMapToFiveShades() {
        XCTAssertEqual([1, 2, 3, 4, 5, 9, 10, 40].map(RouteHeatmap.level(forPasses:)),
                       [0, 1, 2, 2, 3, 3, 4, 4])
    }

    func testThirtyDaysIsTheDefaultWindow() {
        XCTAssertEqual(HeatmapWindow.default, .month)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(HeatmapWindow.month.includes(now.addingTimeInterval(-29 * 86_400), now: now))
        XCTAssertFalse(HeatmapWindow.month.includes(now.addingTimeInterval(-31 * 86_400), now: now))
        XCTAssertTrue(HeatmapWindow.all.includes(.distantPast, now: now))
        XCTAssertFalse(HeatmapWindow.off.includes(now, now: now))
    }

    // MARK: Friends

    private func cells(_ route: [CLLocationCoordinate2D]) -> [RouteHeatmap.Cell] {
        RouteHeatmap.orderedCells(route)
    }

    func testAFriendsStreetAloneIsBlue() {
        let segments = RouteHeatmap.segments(routes: [], friendStreets: [cells(line(40.68, -73.97))])
        XCTAssertFalse(segments.isEmpty)
        XCTAssertEqual(Set(segments.map(\.owner)), [.friends])
    }

    func testAStreetYouAndAFriendBothCoveredIsGreen() {
        let segments = RouteHeatmap.segments(routes: [line(40.68, -73.97)],
                                             friendStreets: [cells(line(40.68, -73.97, eastOffset: 6))])
        XCTAssertEqual(Set(segments.map(\.owner)), [.both], "no blue drawn under or beside the green")
        XCTAssertEqual(Set(segments.map(\.level)), [1], "green is shaded by both passes")
    }

    func testAFriendOnTheNextStreetStaysBlueAndYoursStaysOrange() {
        let segments = RouteHeatmap.segments(routes: [line(40.68, -73.97)],
                                             friendStreets: [cells(line(40.68, -73.97, eastOffset: 80))])
        XCTAssertEqual(Set(segments.map(\.owner)), [.mine, .friends])
    }

    func testGreenDrawsOverOrangeOverBlue() {
        let long = line(40.68, -73.97, meters: 800)
        let friend = cells(line(40.68, -73.97, meters: 300)) + cells(line(40.68, -73.96, meters: 300))
        let owners = RouteHeatmap.segments(routes: [long], friendStreets: [friend]).map(\.owner)
        XCTAssertEqual(owners, owners.sorted())
        XCTAssertEqual(Set(owners), [.friends, .mine, .both])
    }

    func testSharedStreetsTrimBothEndsAndSkipShortActivities() {
        XCTAssertTrue(RouteHeatmap.streetCells(route: line(40.68, -73.97, meters: 350)).isEmpty,
                      "under 400 m there is nothing left once both ends are trimmed")
        let route = line(40.68, -73.97, meters: 1000)
        let shared = RouteHeatmap.streetCells(route: route)
        XCTAssertFalse(shared.isEmpty)
        for c in shared {
            let p = RouteHeatmap.center(c)
            XCTAssertGreaterThan(RouteHeatmap.distance(p, route.first!), RouteHeatmap.privacyTrimMeters - RouteHeatmap.cellMeters)
            XCTAssertGreaterThan(RouteHeatmap.distance(p, route.last!), RouteHeatmap.privacyTrimMeters - RouteHeatmap.cellMeters)
        }
    }

    func testCellsSurviveTheTripToTheServer() {
        for c in [RouteHeatmap.Cell(x: -416_000, y: 299_800), .init(x: 0, y: -1), .init(x: 12, y: 0)] {
            XCTAssertEqual(RouteHeatmap.unpack(RouteHeatmap.pack(c)), c)
        }
    }
}

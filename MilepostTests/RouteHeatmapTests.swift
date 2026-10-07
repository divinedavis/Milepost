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

    func testSharedStreetsDropARadiusAroundBothEndsAndSkipShortActivities() {
        XCTAssertTrue(RouteHeatmap.streetCells(route: line(40.68, -73.97, meters: 800)).isEmpty,
                      "under ~830 m there is nothing left once both ends are cleared")
        let route = line(40.68, -73.97, meters: 1500)
        let shared = RouteHeatmap.streetCells(route: route)
        XCTAssertFalse(shared.isEmpty)
        for c in shared {
            let p = RouteHeatmap.center(c)
            XCTAssertGreaterThan(RouteHeatmap.distance(p, route.first!), RouteHeatmap.privacyRadiusMeters)
            XCTAssertGreaterThan(RouteHeatmap.distance(p, route.last!), RouteHeatmap.privacyRadiusMeters)
        }
    }

    func testALoopPastTheFrontDoorDoesNotShareIt() {
        // Out 1 km north, back, and on 300 m south of the start. Trimming
        // 200 m ALONG the route used to share the street at the front door
        // on the way back; a radius does not.
        let out = line(40.68, -73.97, meters: 1000)
        let south = stride(from: 8.0, through: 300, by: 8).map {
            CLLocationCoordinate2D(latitude: 40.68 - $0 / 110_540, longitude: -73.97)
        }
        let route = out + out.reversed() + south
        for c in RouteHeatmap.streetCells(route: route) {
            XCTAssertGreaterThan(RouteHeatmap.distance(RouteHeatmap.center(c), route.first!),
                                 RouteHeatmap.privacyRadiusMeters)
        }
    }

    func testSharedStreetsAreSortedNotInRouteOrder() {
        let north = RouteHeatmap.streetCells(route: line(40.68, -73.97, meters: 1500))
        let south = RouteHeatmap.streetCells(route: line(40.68, -73.97, meters: 1500).reversed())
        XCTAssertEqual(north, south, "the same street either way: no direction leaves the phone")
        XCTAssertEqual(north.map(RouteHeatmap.pack), north.map(RouteHeatmap.pack).sorted())
    }

    func testFrequentEndpointsAreOnlyThePlacesRepeated() {
        let home = CLLocationCoordinate2D(latitude: 40.68, longitude: -73.97)
        let nearHome = CLLocationCoordinate2D(latitude: 40.6805, longitude: -73.9702)
        let work = CLLocationCoordinate2D(latitude: 40.75, longitude: -73.99)
        let park = CLLocationCoordinate2D(latitude: 40.66, longitude: -73.97)
        let zones = RouteHeatmap.frequentEndpoints([(home, work), (nearHome, park)])
        XCTAssertEqual(zones.count, 2, "home and near-home repeat; work and the park were visited once")
        XCTAssertTrue(zones.allSatisfy { RouteHeatmap.distance($0, home) < RouteHeatmap.privacyRadiusMeters })
    }

    func testAFriendsSortedCellsStillDrawAsOneStreet() {
        // An L-shaped walk, sent as a shuffled set.
        let north = line(40.68, -73.97, meters: 600)
        let lonStep = 8 / (111_320 * cos(40.68 * .pi / 180))
        let corner = north.last!
        let east = (1...60).map { CLLocationCoordinate2D(latitude: corner.latitude, longitude: corner.longitude + Double($0) * lonStep) }
        let street = Array(Set(RouteHeatmap.orderedCells(north + east))).shuffled()
        let chains = RouteHeatmap.chains(street)
        XCTAssertEqual(chains.count, 1, "one street, one line: \(chains.map(\.count))")
        XCTAssertEqual(Set(chains.flatMap { $0 }), Set(street))
        let blue = RouteHeatmap.segments(routes: [], friendStreets: [street])
        XCTAssertFalse(blue.isEmpty)
        XCTAssertEqual(Set(blue.map(\.owner)), [.friends])
    }

    func testCellsSurviveTheTripToTheServer() {
        for c in [RouteHeatmap.Cell(x: -416_000, y: 299_800), .init(x: 0, y: -1), .init(x: 12, y: 0)] {
            XCTAssertEqual(RouteHeatmap.unpack(RouteHeatmap.pack(c)), c)
        }
    }
}

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
}

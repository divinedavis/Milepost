import CoreLocation
import Testing
@testable import Milepost

/// Swift Testing (the first of Apple's four ship checks): the street-sharing
/// privacy promise, parameterized over route shapes. Whatever shape a run
/// takes, no shared cell sits within 400 m of where it started or finished,
/// and nothing about its order survives.
struct StreetPrivacySwiftTests {
    enum Shape: String, CaseIterable, CustomTestStringConvertible {
        case straight, outAndBack, loop, lollipop, zigzag
        var testDescription: String { rawValue }

        /// Metres east/north from a Brooklyn origin, a fix every ~8 m.
        var route: [CLLocationCoordinate2D] {
            func pts(_ legs: [(Double, Double)]) -> [CLLocationCoordinate2D] {
                var out: [(Double, Double)] = [(0, 0)]
                for (dx, dy) in legs {
                    let (x0, y0) = out.last!
                    let n = max(1, Int((dx * dx + dy * dy).squareRoot() / 8))
                    for i in 1...n {
                        out.append((x0 + dx * Double(i) / Double(n), y0 + dy * Double(i) / Double(n)))
                    }
                }
                let lat0 = 40.68, lon0 = -73.97
                return out.map {
                    CLLocationCoordinate2D(latitude: lat0 + $0.1 / 110_540,
                                           longitude: lon0 + $0.0 / (111_320 * cos(lat0 * .pi / 180)))
                }
            }
            switch self {
            case .straight: return pts([(0, 2000)])
            case .outAndBack: return pts([(0, 1500), (0, -1500)])
            case .loop: return pts([(0, 800), (800, 0), (0, -800), (-800, 0)])
            case .lollipop: return pts([(0, 500), (600, 600), (-600, 600), (0, -1200), (0, -500)])
            case .zigzag: return pts([(300, 300), (300, -300), (300, 300), (300, -300), (300, 300)])
            }
        }
    }

    @Test(arguments: Shape.allCases)
    func nothingNearEitherEnd(_ shape: Shape) {
        let route = shape.route
        for cell in RouteHeatmap.streetCells(route: route) {
            let p = RouteHeatmap.center(cell)
            #expect(RouteHeatmap.distance(p, route.first!) > RouteHeatmap.privacyRadiusMeters)
            #expect(RouteHeatmap.distance(p, route.last!) > RouteHeatmap.privacyRadiusMeters)
        }
    }

    @Test(arguments: Shape.allCases)
    func directionDoesNotLeaveThePhone(_ shape: Shape) {
        let forward = RouteHeatmap.streetCells(route: shape.route)
        let backward = RouteHeatmap.streetCells(route: shape.route.reversed())
        #expect(forward == backward)
        let packed = forward.map(RouteHeatmap.pack)
        #expect(packed == packed.sorted())
        #expect(Set(packed).count == packed.count)
    }

    @Test(arguments: Shape.allCases)
    func whatIsSharedStillDraws(_ shape: Shape) {
        let cells = RouteHeatmap.streetCells(route: shape.route)
        let chains = RouteHeatmap.chains(cells.shuffled())
        #expect(Set(chains.flatMap { $0 }) == Set(cells.filter { c in
            cells.contains { o in o != c && abs(o.x - c.x) <= 1 && abs(o.y - c.y) <= 1 }
        }))
    }
}

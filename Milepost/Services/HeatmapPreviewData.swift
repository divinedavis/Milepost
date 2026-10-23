#if DEBUG
import CoreLocation
import Foundation
import SwiftData

/// Three past walks around the simulator's pinned fix (40.6835,-73.9680) for
/// `-uitest-seed-heatmap`: two this month that share Vanderbilt Ave and so
/// darken it, and one 60 days back that only a wider window shows.
enum HeatmapPreviewData {
    static func seed(into context: ModelContext, now: Date = .now) {
        let loopA = [(40.6835, -73.9680), (40.6880, -73.9690), (40.6885, -73.9645),
                     (40.6840, -73.9635), (40.6835, -73.9680)]
        let loopB = [(40.6835, -73.9680), (40.6880, -73.9690), (40.6875, -73.9735),
                     (40.6830, -73.9725), (40.6835, -73.9680)]
        let old = [(40.6835, -73.9680), (40.6790, -73.9670), (40.6795, -73.9620),
                   (40.6840, -73.9635)]
        let walks: [(String, Int, [(Double, Double)])] = [
            ("Heatmap A", 2, loopA), ("Heatmap B", 9, loopB), ("Heatmap old", 60, old),
        ]
        for (title, daysAgo, corners) in walks {
            let start = now.addingTimeInterval(-Double(daysAgo) * 86_400)
            let route = densify(corners, start: start)
            let meters = zip(route, route.dropFirst()).reduce(0.0) {
                $0 + RouteHeatmap.distance($1.0.coordinate, $1.1.coordinate)
            }
            let seconds = meters / 1.4
            context.insert(Activity(title: title, startDate: start,
                                    endDate: start.addingTimeInterval(seconds),
                                    movingSeconds: seconds, distanceMeters: meters,
                                    splitMeters: DistanceUnit.miles.meters,
                                    route: route, splits: [], sport: .walk))
        }
        try? context.save()
    }

    /// What a walk the app died halfway through leaves on disk: half a loop
    /// of Prospect Heights, started 40 minutes ago, last written 25 minutes
    /// ago. For `-uitest-seed-checkpoint`.
    static func interruptedWalk(now: Date = .now) -> RunCheckpoint {
        let start = now.addingTimeInterval(-40 * 60)
        let route = densify([(40.6835, -73.9680), (40.6880, -73.9690), (40.6885, -73.9645)], start: start)
        let meters = zip(route, route.dropFirst()).reduce(0.0) {
            $0 + RouteHeatmap.distance($1.0.coordinate, $1.1.coordinate)
        }
        return RunCheckpoint(sport: .walk, splitMeters: DistanceUnit.miles.meters, startDate: start,
                             savedAt: now.addingTimeInterval(-25 * 60), movingSeconds: 15 * 60,
                             distanceMeters: meters, route: route,
                             splits: [Split(index: 1, distanceMeters: meters, seconds: 15 * 60)],
                             pauses: [])
    }

    /// A fix every ~8 m along the corners, like a 1 Hz walk.
    private static func densify(_ corners: [(Double, Double)], start: Date) -> [RoutePoint] {
        var out: [RoutePoint] = []
        var t = start
        for (a, b) in zip(corners, corners.dropFirst()) {
            let ca = CLLocationCoordinate2D(latitude: a.0, longitude: a.1)
            let cb = CLLocationCoordinate2D(latitude: b.0, longitude: b.1)
            let steps = max(1, Int(RouteHeatmap.distance(ca, cb) / 8))
            for s in 0..<steps {
                let f = Double(s) / Double(steps)
                out.append(RoutePoint(latitude: a.0 + (b.0 - a.0) * f,
                                      longitude: a.1 + (b.1 - a.1) * f, timestamp: t))
                t.addTimeInterval(6)
            }
        }
        if let last = corners.last {
            out.append(RoutePoint(latitude: last.0, longitude: last.1, timestamp: t))
        }
        return out
    }
}
#endif

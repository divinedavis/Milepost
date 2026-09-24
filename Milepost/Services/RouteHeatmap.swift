import CoreLocation
import Foundation
import SwiftUI

/// How far back the Record map's heatmap of past activities looks. 30 days
/// by default (user request, 2026-09-24): recent enough to show where you
/// run now, long enough that a regular loop has built up colour.
enum HeatmapWindow: String, CaseIterable, Identifiable {
    case week, month, quarter, all, off

    static let storageKey = "record.heatmapWindow"
    static let `default`: HeatmapWindow = .month

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .quarter: 90
        case .all, .off: nil
        }
    }

    var title: String {
        switch self {
        case .week: "7 days"
        case .month: "30 days"
        case .quarter: "90 days"
        case .all: "All time"
        case .off: "Off"
        }
    }

    func includes(_ date: Date, now: Date = .now) -> Bool {
        switch self {
        case .off: return false
        case .all: return true
        default:
            guard let days else { return true }
            return date >= now.addingTimeInterval(-Double(days) * 86_400)
        }
    }
}

/// A stretch of one past route, coloured by how many activities covered it.
struct HeatSegment: Identifiable, Equatable {
    let id: Int
    /// 0 = covered once. See `RouteHeatmap.level(forPasses:)`.
    let level: Int
    let coordinates: [CLLocationCoordinate2D]

    static func == (a: HeatSegment, b: HeatSegment) -> Bool {
        a.id == b.id && a.level == b.level && a.coordinates.count == b.coordinates.count
    }
}

/// Past routes as a heatmap: a street covered once is light orange, and it
/// darkens each time another activity covers it again.
///
/// "The same street" is decided on a 15 m grid. Two runs down one block
/// never share GPS fixes — they wander 5-10 m apart — so each activity
/// claims the cells its route crosses **plus their neighbours**, and a
/// point's pass count is how many activities claimed its cell. A block away
/// (60 m+ in Brooklyn) is four cells off and never counts. An activity
/// counts once per cell however many times it loops through, so one run
/// round a track does not read as ten.
enum RouteHeatmap {
    static let cellMeters = 15.0
    /// Fixes further apart than this are a pause or a GPS dropout: no line
    /// is drawn across the gap and no cells are claimed along it.
    static let gapMeters = 200.0
    /// Points closer than this to the last kept one are dropped from the
    /// drawn line; the cells have already been claimed.
    static let simplifyMeters = 5.0

    /// Light to dark orange. Level 0 is one pass.
    static let colors: [Color] = [
        Color(red: 1.00, green: 0.83, blue: 0.66), // #FFD4A8
        Color(red: 1.00, green: 0.69, blue: 0.40), // #FFB066
        Color(red: 1.00, green: 0.54, blue: 0.17), // #FF8A2B
        Color(red: 0.91, green: 0.40, blue: 0.04), // #E8660A
        Color(red: 0.72, green: 0.29, blue: 0.00), // #B84A00
    ]

    static func level(forPasses passes: Int) -> Int {
        switch passes {
        case ...1: 0
        case 2: 1
        case 3...4: 2
        case 5...9: 3
        default: 4
        }
    }

    static func color(level: Int) -> Color {
        colors[min(max(level, 0), colors.count - 1)]
    }

    struct Cell: Hashable {
        let x: Int
        let y: Int
    }

    /// Equirectangular metres. The x scale uses the point's own latitude, so
    /// a place always lands in the same cell; the slight squeeze between
    /// latitudes is far smaller than a cell.
    static func cell(_ c: CLLocationCoordinate2D) -> Cell {
        let y = c.latitude * 110_540 / cellMeters
        let x = c.longitude * 111_320 * cos(c.latitude * .pi / 180) / cellMeters
        return Cell(x: Int(x.rounded(.down)), y: Int(y.rounded(.down)))
    }

    /// Every activity's route, in; coloured stretches, out, lightest first so
    /// the darker ones draw on top where routes cross.
    static func segments(routes: [[CLLocationCoordinate2D]]) -> [HeatSegment] {
        var passes: [Cell: Int] = [:]
        for route in routes {
            for cell in claimedCells(route) { passes[cell, default: 0] += 1 }
        }

        var out: [(level: Int, coords: [CLLocationCoordinate2D])] = []
        for route in routes where route.count > 1 {
            let levels = route.map { level(forPasses: passes[cell($0)] ?? 1) }
            var current: [CLLocationCoordinate2D] = [route[0]]
            var currentLevel: Int?
            func flush() {
                if current.count > 1, let currentLevel { out.append((currentLevel, current)) }
            }
            for i in 1..<route.count {
                let a = route[i - 1], b = route[i]
                if distance(a, b) > gapMeters {
                    flush()
                    current = [b]
                    currentLevel = nil
                    continue
                }
                // A stretch is as dark as its lighter end, so a street only
                // darkens where both ends of it were covered again.
                let segLevel = min(levels[i - 1], levels[i])
                if let lvl = currentLevel, lvl != segLevel {
                    // `a` may have been simplified away; end exactly on it
                    // so the two colours meet with no gap.
                    if let last = current.last, last.latitude != a.latitude || last.longitude != a.longitude {
                        current.append(a)
                    }
                    flush()
                    current = [a]
                }
                currentLevel = segLevel
                if let last = current.last, distance(last, b) < simplifyMeters, i < route.count - 1 {
                    continue
                }
                current.append(b)
            }
            flush()
        }

        return out.enumerated()
            .sorted { ($0.element.level, $0.offset) < ($1.element.level, $1.offset) }
            .enumerated()
            .map { HeatSegment(id: $0.offset, level: $0.element.element.level, coordinates: $0.element.element.coords) }
    }

    /// The cells one route passes through, filled in along straight stretches
    /// between sparse fixes, then widened by a cell each way.
    static func claimedCells(_ route: [CLLocationCoordinate2D]) -> Set<Cell> {
        var core = Set<Cell>()
        for (i, point) in route.enumerated() {
            core.insert(cell(point))
            guard i > 0 else { continue }
            let prev = route[i - 1]
            let d = distance(prev, point)
            guard d > cellMeters / 2, d <= gapMeters else { continue }
            let steps = Int((d / (cellMeters / 2)).rounded(.up))
            for s in 1..<steps {
                let t = Double(s) / Double(steps)
                core.insert(cell(CLLocationCoordinate2D(
                    latitude: prev.latitude + (point.latitude - prev.latitude) * t,
                    longitude: prev.longitude + (point.longitude - prev.longitude) * t)))
            }
        }
        var widened = Set<Cell>()
        for c in core {
            for dx in -1...1 {
                for dy in -1...1 { widened.insert(Cell(x: c.x + dx, y: c.y + dy)) }
            }
        }
        return widened
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let dy = (b.latitude - a.latitude) * 110_540
        let dx = (b.longitude - a.longitude) * 111_320 * cos((a.latitude + b.latitude) / 2 * .pi / 180)
        return (dx * dx + dy * dy).squareRoot()
    }
}

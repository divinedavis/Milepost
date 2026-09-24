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

/// Whose streets a stretch is: yours (orange), a friend's (blue), or both
/// (green). Declared in drawing order: both goes on top.
enum HeatOwner: Int, Comparable {
    case friends, mine, both

    static func < (a: HeatOwner, b: HeatOwner) -> Bool { a.rawValue < b.rawValue }
}

/// A stretch of one past route, coloured by whose it is and how many
/// activities covered it.
struct HeatSegment: Identifiable, Equatable {
    let id: Int
    let owner: HeatOwner
    /// 0 = covered once. See `RouteHeatmap.level(forPasses:)`.
    let level: Int
    let coordinates: [CLLocationCoordinate2D]

    var color: Color { RouteHeatmap.color(owner: owner, level: level) }

    static func == (a: HeatSegment, b: HeatSegment) -> Bool {
        a.id == b.id && a.owner == b.owner && a.level == b.level && a.coordinates.count == b.coordinates.count
    }
}

/// Past routes as a heatmap: a street covered once is light orange, and it
/// darkens each time another activity covers it again. Friends' streets (if
/// they opted in to share them) are blue, and a street both you and a friend
/// covered is green.
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

    /// Friends' streets, light to dark blue.
    static let friendColors: [Color] = [
        Color(red: 0.66, green: 0.80, blue: 1.00), // #A8CCFF
        Color(red: 0.47, green: 0.67, blue: 1.00), // #78ABFF
        Color(red: 0.29, green: 0.54, blue: 1.00), // #4A8AFF
        Color(red: 0.13, green: 0.42, blue: 0.93), // #216BED
        Color(red: 0.05, green: 0.31, blue: 0.78), // #0D4FC7
    ]

    /// Streets you and a friend both covered, light to dark green.
    static let sharedColors: [Color] = [
        Color(red: 0.70, green: 0.93, blue: 0.64), // #B3EDA3
        Color(red: 0.51, green: 0.87, blue: 0.43), // #82DE6E
        Color(red: 0.33, green: 0.78, blue: 0.25), // #54C740
        Color(red: 0.20, green: 0.65, blue: 0.13), // #33A621
        Color(red: 0.11, green: 0.50, blue: 0.06), // #1C800F
    ]

    static func color(level: Int) -> Color { color(owner: .mine, level: level) }

    static func color(owner: HeatOwner, level: Int) -> Color {
        let palette: [Color]
        switch owner {
        case .mine: palette = colors
        case .friends: palette = friendColors
        case .both: palette = sharedColors
        }
        return palette[min(max(level, 0), palette.count - 1)]
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

    /// Every activity's route and every friend's shared street cells, in;
    /// coloured stretches, out. Blue under orange under green, and lightest
    /// first within each, so darker stretches draw on top where routes cross.
    static func segments(routes: [[CLLocationCoordinate2D]],
                         friendStreets: [[Cell]] = []) -> [HeatSegment] {
        var passes: [Cell: Int] = [:]
        for route in routes {
            for cell in claimedCells(route) { passes[cell, default: 0] += 1 }
        }
        var friendPasses: [Cell: Int] = [:]
        for street in friendStreets {
            for cell in widen(Set(street)) { friendPasses[cell, default: 0] += 1 }
        }

        typealias Piece = (key: Key, coords: [CLLocationCoordinate2D])
        var out: [Piece] = []

        for route in routes where route.count > 1 {
            // A point is shared when a friend covered its cell too; green is
            // shaded by everyone's passes together.
            let keys: [Key] = route.map {
                let c = cell($0)
                let mine = passes[c] ?? 1
                if let theirs = friendPasses[c] {
                    return Key(owner: .both, level: level(forPasses: mine + theirs))
                }
                return Key(owner: .mine, level: level(forPasses: mine))
            }
            var current: [CLLocationCoordinate2D] = [route[0]]
            var currentKey: Key?
            func flush() {
                if current.count > 1, let currentKey { out.append((currentKey, current)) }
            }
            for i in 1..<route.count {
                let a = route[i - 1], b = route[i]
                if distance(a, b) > gapMeters {
                    flush()
                    current = [b]
                    currentKey = nil
                    continue
                }
                // A stretch is as dark as its lighter end, so a street only
                // darkens where both ends of it were covered again, and only
                // turns green where a friend covered both ends.
                let segKey = Key.weaker(keys[i - 1], keys[i])
                if let key = currentKey, key != segKey {
                    // `a` may have been simplified away; end exactly on it
                    // so the two colours meet with no gap.
                    if let last = current.last, last.latitude != a.latitude || last.longitude != a.longitude {
                        current.append(a)
                    }
                    flush()
                    current = [a]
                }
                currentKey = segKey
                if let last = current.last, distance(last, b) < simplifyMeters, i < route.count - 1 {
                    continue
                }
                current.append(b)
            }
            flush()
        }

        // Friends' streets that are not yours: blue, drawn through the cell
        // centres. Where you covered it too your own line is already green.
        var mine = Set<Cell>()
        for route in routes { mine.formUnion(claimedCells(route)) }
        for street in friendStreets where street.count > 1 {
            var current: [CLLocationCoordinate2D] = []
            var currentKey: Key?
            func flush() {
                if current.count > 1, let currentKey { out.append((currentKey, smooth(current))) }
                current = []
                currentKey = nil
            }
            for i in 1..<street.count {
                let a = street[i - 1], b = street[i]
                let adjacent = abs(a.x - b.x) <= 2 && abs(a.y - b.y) <= 2
                guard adjacent, !(mine.contains(a) && mine.contains(b)) else {
                    flush()
                    continue
                }
                let key = Key(owner: .friends,
                              level: level(forPasses: min(friendPasses[a] ?? 1, friendPasses[b] ?? 1)))
                if let currentKey, currentKey != key { flush() }
                if current.isEmpty { current = [center(a)] }
                current.append(center(b))
                currentKey = key
            }
            flush()
        }

        return out.enumerated()
            .sorted { ($0.element.key, $0.offset) < ($1.element.key, $1.offset) }
            .enumerated()
            .map { HeatSegment(id: $0.offset, owner: $0.element.element.key.owner,
                               level: $0.element.element.key.level, coordinates: $0.element.element.coords) }
    }

    struct Key: Hashable, Comparable {
        let owner: HeatOwner
        let level: Int

        static func < (a: Key, b: Key) -> Bool { (a.owner, a.level) < (b.owner, b.level) }

        /// Of a stretch's two ends, the one that decides its colour: mine
        /// beats both (green needs a friend at each end), then the lighter.
        static func weaker(_ a: Key, _ b: Key) -> Key {
            if a.owner != b.owner { return Key(owner: .mine, level: min(a.level, b.level)) }
            return a.level <= b.level ? a : b
        }
    }

    /// Cell centres step like a staircase along any street that is not
    /// north-south or east-west. Douglas-Peucker at under a cell's width
    /// straightens the steps without leaving the street.
    static func smooth(_ line: [CLLocationCoordinate2D], tolerance: Double = cellMeters * 0.8) -> [CLLocationCoordinate2D] {
        guard line.count > 2 else { return line }
        func offset(_ p: CLLocationCoordinate2D, _ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
            let k = 111_320 * cos(a.latitude * .pi / 180)
            let (bx, by) = ((b.longitude - a.longitude) * k, (b.latitude - a.latitude) * 110_540)
            let (px, py) = ((p.longitude - a.longitude) * k, (p.latitude - a.latitude) * 110_540)
            let len = (bx * bx + by * by).squareRoot()
            guard len > 0 else { return (px * px + py * py).squareRoot() }
            return abs(px * by - py * bx) / len
        }
        var keep = [Bool](repeating: false, count: line.count)
        keep[0] = true
        keep[line.count - 1] = true
        var stack = [(0, line.count - 1)]
        while let (i, j) = stack.popLast() {
            guard j > i + 1 else { continue }
            var worst = 0.0, at = i
            for k in (i + 1)..<j {
                let d = offset(line[k], line[i], line[j])
                if d > worst { worst = d; at = k }
            }
            if worst > tolerance {
                keep[at] = true
                stack.append((i, at))
                stack.append((at, j))
            }
        }
        return zip(line, keep).filter(\.1).map(\.0)
    }

    /// The middle of a cell, for drawing a friend's street from its cells.
    static func center(_ c: Cell) -> CLLocationCoordinate2D {
        let lat = (Double(c.y) + 0.5) * cellMeters / 110_540
        let lon = (Double(c.x) + 0.5) * cellMeters / (111_320 * cos(lat * .pi / 180))
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// The cells one route passes through, filled in along straight stretches
    /// between sparse fixes, then widened by a cell each way.
    static func claimedCells(_ route: [CLLocationCoordinate2D]) -> Set<Cell> {
        widen(Set(orderedCells(route)))
    }

    /// The cells a route passes through, in the order it passes them, each
    /// once per visit. Straight stretches between sparse fixes are filled in;
    /// a gap is not.
    static func orderedCells(_ route: [CLLocationCoordinate2D]) -> [Cell] {
        var out: [Cell] = []
        func add(_ c: Cell) { if out.last != c { out.append(c) } }
        for (i, point) in route.enumerated() {
            if i > 0 {
                let prev = route[i - 1]
                let d = distance(prev, point)
                if d > cellMeters / 2, d <= gapMeters {
                    let steps = Int((d / (cellMeters / 2)).rounded(.up))
                    for s in 1..<steps {
                        let t = Double(s) / Double(steps)
                        add(cell(CLLocationCoordinate2D(
                            latitude: prev.latitude + (point.latitude - prev.latitude) * t,
                            longitude: prev.longitude + (point.longitude - prev.longitude) * t)))
                    }
                }
            }
            add(cell(point))
        }
        return out
    }

    static func widen(_ core: Set<Cell>) -> Set<Cell> {
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

// MARK: Sharing streets with friends

extension RouteHeatmap {
    /// Nothing within this far of either end of an activity is shared: where
    /// a run starts and ends is usually where someone lives.
    static let privacyTrimMeters = 200.0
    /// The server refuses a row with more cells than this.
    static let maxSharedCells = 10_000

    /// What a friend receives for one activity: the street cells in order,
    /// with both ends trimmed. No times, no speeds, no exact fixes. Empty if
    /// the activity is too short to have anything left after trimming.
    static func streetCells(route: [CLLocationCoordinate2D]) -> [Cell] {
        guard route.count > 1 else { return [] }
        var along = [0.0]
        for (a, b) in zip(route, route.dropFirst()) {
            along.append(along.last! + distance(a, b))
        }
        let total = along.last!
        guard total > privacyTrimMeters * 2 else { return [] }
        let middle = zip(route, along)
            .filter { $0.1 >= privacyTrimMeters && $0.1 <= total - privacyTrimMeters }
            .map(\.0)
        return Array(orderedCells(middle).prefix(maxSharedCells))
    }

    /// A cell as one bigint for the server: x in the high 32 bits, y in the low.
    static func pack(_ c: Cell) -> Int64 {
        (Int64(Int32(truncatingIfNeeded: c.x)) << 32) | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: c.y)))
    }

    static func unpack(_ v: Int64) -> Cell {
        Cell(x: Int(Int32(truncatingIfNeeded: v >> 32)), y: Int(Int32(truncatingIfNeeded: v)))
    }
}

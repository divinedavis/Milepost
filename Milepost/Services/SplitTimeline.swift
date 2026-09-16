import Foundation

/// Turns Milepost's splits — which carry a distance and a duration but no
/// dates — into absolute date ranges.
///
/// Apple Health stores a workout's laps as `HKWorkoutActivity` segments, and a
/// segment is defined by when it started and ended, not by how long it lasted.
/// The route's own timestamps are the source: each fix carries the distance the
/// recorder had booked at that moment, so a split boundary is a straight
/// interpolation between the two fixes that straddle it. Reconstructing the
/// same thing from moving time would put every boundary in the wrong place on
/// any activity that was paused.
enum SplitTimeline {
    /// A split and when it happened. The split travels with its dates on
    /// purpose: a range that has to be dropped (see below) would otherwise
    /// shift every later split onto the wrong one, and the caller pairing them
    /// back up by position would never notice.
    struct DatedSplit: Equatable {
        let split: Split
        let start: Date
        let end: Date
    }

    /// One entry per split that could be placed, in order. Empty when the
    /// activity has no usable route — a segment guessed from duration alone
    /// would claim a precision Health has no way to know is fictional.
    static func ranges(splits: [Split],
                       splitMeters: Double,
                       route: [RoutePoint],
                       startDate: Date,
                       endDate: Date) -> [DatedSplit] {
        guard splitMeters > 0, !splits.isEmpty else { return [] }
        let measured = route.filter { $0.cumulativeMeters != nil }
        guard measured.count >= 2 else { return [] }

        var out: [DatedSplit] = []
        var cursor = max(startDate, measured[0].timestamp)
        for split in splits {
            let boundary = Double(split.index) * splitMeters
            let end: Date
            if split.isComplete(splitMeters: splitMeters), let crossing = date(crossing: boundary, in: measured) {
                end = crossing
            } else {
                end = endDate
            }
            // Clock skew between fixes can hand back an end before the start;
            // a zero-length segment is rejected by HealthKit, so drop it.
            guard end > cursor else { continue }
            out.append(DatedSplit(split: split, start: cursor, end: end))
            cursor = end
        }
        return out
    }

    /// The instant the activity passed `meters`, interpolated between the two
    /// fixes either side of it.
    static func date(crossing meters: Double, in measured: [RoutePoint]) -> Date? {
        guard let first = measured.first, let last = measured.last,
              let firstMeters = first.cumulativeMeters, let lastMeters = last.cumulativeMeters,
              meters > firstMeters, meters <= lastMeters else { return nil }
        for (previous, point) in zip(measured, measured.dropFirst()) {
            guard let a = previous.cumulativeMeters, let b = point.cumulativeMeters, b >= meters else { continue }
            let span = b - a
            guard span > 0 else { return point.timestamp }
            let fraction = (meters - a) / span
            let seconds = point.timestamp.timeIntervalSince(previous.timestamp)
            return previous.timestamp.addingTimeInterval(seconds * fraction)
        }
        return last.timestamp
    }

    /// Total climb along the route, in meters. Only fixes with a real altitude
    /// count, and only rises past `threshold` — a barometer wanders by a meter
    /// or two standing still, and summing that noise over an hour invents
    /// hundreds of feet of elevation.
    static func elevationAscended(route: [RoutePoint], threshold: Double = 1.0) -> Double? {
        let altitudes = route.compactMap { point -> Double? in
            guard let altitude = point.altitude,
                  let vertical = point.verticalAccuracy, vertical >= 0 else { return nil }
            return altitude
        }
        guard altitudes.count >= 2 else { return nil }
        var gain = 0.0
        var reference = altitudes[0]
        for altitude in altitudes.dropFirst() {
            let delta = altitude - reference
            if delta >= threshold {
                gain += delta
                reference = altitude
            } else if delta <= -threshold {
                reference = altitude
            }
        }
        return gain
    }

    /// Total descent, measured the same way.
    static func elevationDescended(route: [RoutePoint], threshold: Double = 1.0) -> Double? {
        let flipped = route.map { point -> RoutePoint in
            var copy = point
            copy.altitude = point.altitude.map { -$0 }
            return copy
        }
        return elevationAscended(route: flipped, threshold: threshold)
    }
}

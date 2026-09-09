import CoreLocation
import Foundation
import Observation

struct RunSummary: Equatable {
    var startDate: Date
    var endDate: Date
    var movingSeconds: TimeInterval
    var distanceMeters: Double
    var splitMeters: Double
    var route: [RoutePoint]
    var splits: [Split]
    var sport: Sport
}

/// The recording engine. Pure state + arithmetic: it is fed CLLocations by
/// whoever owns the location manager and told the time by an injectable
/// clock, so every rule below is unit-testable without GPS.
@MainActor
@Observable
final class RunRecorder {
    enum State: Equatable { case idle, recording, paused }

    /// Below this a finished run is "No Movement Detected" and cannot be saved.
    static let minimumMovementMeters: Double = 10
    /// Fixes worse than this are jitter, not running. Strava uses about the same.
    static let maxHorizontalAccuracy: CLLocationAccuracy = 25
    /// A step shorter than this is drift while standing still.
    static let minimumStepMeters: Double = 1
    /// CoreLocation's own speed estimate below this means "not moving".
    static let stationarySpeed: CLLocationSpeed = 0.3

    private(set) var state: State = .idle
    private(set) var distanceMeters: Double = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var route: [RoutePoint] = []
    private(set) var splits: [Split] = []
    private(set) var startDate: Date?
    private(set) var unit: DistanceUnit = .miles
    private(set) var sport: Sport = .run

    /// Fired each time the run crosses a half-unit boundary (0.5, 1, 1.5 …).
    /// The voice announcer decides which of those to say; the engine has no
    /// idea what a setting is.
    var onMilestone: (@MainActor (Milestone) -> Void)?
    private var nextMilestoneMeters: Double = 0

    private var accumulated: TimeInterval = 0
    private var segmentStart: Date?
    private var lastAccepted: CLLocation?
    private var ticker: Timer?
    private let now: () -> Date

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    var splitMeters: Double { unit.meters }
    var milestoneMeters: Double { unit.meters / 2 }
    var isActive: Bool { state != .idle }
    var hasMovement: Bool { distanceMeters >= Self.minimumMovementMeters }
    var currentSplit: Split? { splits.last }
    var currentSplitPace: Double? { currentSplit?.pace(unit: unit, sport: sport) }
    /// The pace of the last split that ran the full distance. Unlike
    /// `averagePace` this does not move between GPS fixes.
    var previousSplitPace: Double? {
        splits.dropLast().last.flatMap { $0.pace(unit: unit, sport: sport) }
    }
    var averagePace: Double? {
        Pace.secondsPerUnit(distanceMeters: distanceMeters, seconds: elapsed, unit: unit, sport: sport)
    }
    /// The instant a stopwatch would have started to read `elapsed` right
    /// now; nil while paused. Stable for the whole recording segment, so a
    /// clock counting from it (the Live Activity's) needs no update per second.
    var elapsedAnchor: Date? {
        segmentStart.map { $0.addingTimeInterval(-accumulated) }
    }

    // MARK: Lifecycle

    func start(unit: DistanceUnit, sport: Sport = .run) {
        guard state == .idle else { return }
        self.unit = unit
        self.sport = sport
        distanceMeters = 0
        elapsed = 0
        accumulated = 0
        route = []
        splits = [Split(index: 1, distanceMeters: 0, seconds: 0)]
        nextMilestoneMeters = milestoneMeters
        lastAccepted = nil
        let t = now()
        startDate = t
        segmentStart = t
        state = .recording
        startTicker()
    }

    func pause() {
        guard state == .recording, let seg = segmentStart else { return }
        accumulated += now().timeIntervalSince(seg)
        segmentStart = nil
        // The next fix after a resume must not add the distance covered while
        // paused, so the anchor is dropped here.
        lastAccepted = nil
        state = .paused
        stopTicker()
        refreshElapsed()
    }

    func resume() {
        guard state == .paused else { return }
        segmentStart = now()
        state = .recording
        startTicker()
        refreshElapsed()
    }

    /// Stops the clock and hands back what was recorded, or nil when the run
    /// never moved. The recorder stays paused either way so the caller can
    /// offer Resume; call `discard()` once the summary is saved or dropped.
    func finish() -> RunSummary? {
        guard isActive else { return nil }
        if state == .recording { pause() }
        guard hasMovement, let startDate else { return nil }
        return RunSummary(startDate: startDate,
                          endDate: now(),
                          movingSeconds: elapsed,
                          distanceMeters: distanceMeters,
                          splitMeters: splitMeters,
                          route: route,
                          splits: splits,
                          sport: sport)
    }

    func discard() {
        stopTicker()
        state = .idle
        segmentStart = nil
        lastAccepted = nil
        startDate = nil
        accumulated = 0
        elapsed = 0
        distanceMeters = 0
        route = []
        splits = []
    }

    func refreshElapsed() {
        elapsed = accumulated + (segmentStart.map { now().timeIntervalSince($0) } ?? 0)
    }

    // MARK: Location

    func ingest(_ location: CLLocation) {
        guard state == .recording, let seg = segmentStart else { return }
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= Self.maxHorizontalAccuracy else { return }
        // A cached fix from before this segment began would add ground we
        // never covered while recording.
        guard location.timestamp >= seg.addingTimeInterval(-1) else { return }

        guard let last = lastAccepted else {
            lastAccepted = location
            route.append(RoutePoint(location))
            return
        }

        if location.speed >= 0, location.speed < Self.stationarySpeed {
            // Standing still: move the anchor so drift does not pile up, but
            // count nothing.
            lastAccepted = location
            return
        }

        let step = location.distance(from: last)
        guard step >= Self.minimumStepMeters else { return }
        let seconds = max(0, location.timestamp.timeIntervalSince(last.timestamp))

        add(distance: step, seconds: seconds)
        distanceMeters += step
        route.append(RoutePoint(location))
        lastAccepted = location
        emitMilestones(step: step, seconds: seconds)
    }

    /// One step can cross several boundaries (a long GPS gap); each gets its
    /// own milestone with the moving time pro-rated to the crossing.
    private func emitMilestones(step: Double, seconds: TimeInterval) {
        guard distanceMeters >= nextMilestoneMeters else { return }
        refreshElapsed()
        while distanceMeters >= nextMilestoneMeters {
            let overshoot = distanceMeters - nextMilestoneMeters
            let after = step > 0 ? min(1, overshoot / step) * seconds : 0
            let milestone = Milestone(distanceMeters: nextMilestoneMeters,
                                      elapsed: max(0, elapsed - after),
                                      unit: unit,
                                      sport: sport)
            nextMilestoneMeters += milestoneMeters
            onMilestone?(milestone)
        }
    }

    /// Books a step against the current split, rolling any overflow — time
    /// pro-rated by distance — into a fresh split.
    private func add(distance: Double, seconds: TimeInterval) {
        var remainingDistance = distance
        var remainingSeconds = seconds
        while remainingDistance > 0 {
            var current = splits.removeLast()
            let room = splitMeters - current.distanceMeters
            if remainingDistance < room {
                current.distanceMeters += remainingDistance
                current.seconds += remainingSeconds
                splits.append(current)
                remainingDistance = 0
            } else {
                let fraction = room / remainingDistance
                let used = remainingSeconds * fraction
                current.distanceMeters = splitMeters
                current.seconds += used
                splits.append(current)
                splits.append(Split(index: current.index + 1, distanceMeters: 0, seconds: 0))
                remainingDistance -= room
                remainingSeconds -= used
            }
        }
    }

    // MARK: Ticker

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshElapsed() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}

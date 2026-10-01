import CoreLocation
import Foundation
import Observation

/// The Auto-pause switch (You > Settings). Off by default: a clock that stops
/// on its own is a surprise nobody asked for, and slow joggers can sit near
/// the run threshold. The watch gets the phone's value over the application
/// context, like the voice settings.
enum AutoPauseSettings {
    static let enabledKey = "autoPause.enabled"
    static let enabledDefault = false

    static func isEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: enabledKey) as? Bool ?? enabledDefault
    }
}

struct RunSummary: Equatable {
    var startDate: Date
    var endDate: Date
    var movingSeconds: TimeInterval
    var distanceMeters: Double
    var splitMeters: Double
    var route: [RoutePoint]
    var splits: [Split]
    var sport: Sport
    /// Every stretch where the clock was stopped, so Apple Health can be told
    /// the same moving time Milepost shows.
    var pauses: [PauseInterval] = []
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
    private(set) var pauses: [PauseInterval] = []
    /// Chosen at `start` from the user's setting; fixed for the whole run.
    private(set) var autoPauseEnabled = false
    /// True while the clock is stopped because the runner stopped (or, on a
    /// run, slowed to a walk), as opposed to the Pause button. Only an
    /// automatic pause resumes itself.
    private(set) var isAutoPaused = false

    /// Fired with true when auto-pause stops the clock and false when it
    /// starts it again. The watch needs it to pause its workout session too;
    /// the phone just observes `state`.
    var onAutoPauseChange: (@MainActor (Bool) -> Void)?

    /// Fired each time the run crosses a half-unit boundary (0.5, 1, 1.5 …).
    /// The voice announcer decides which of those to say; the engine has no
    /// idea what a setting is.
    var onMilestone: (@MainActor (Milestone) -> Void)?
    private var nextMilestoneMeters: Double = 0

    private var accumulated: TimeInterval = 0
    private var segmentStart: Date?
    private var lastAccepted: CLLocation?
    private var ticker: Timer?
    /// First moment of the current slow stretch while recording, and of the
    /// current fast stretch while auto-paused. Nil when the last fix broke it.
    private var slowSince: Date?
    private var fastSince: Date?
    /// The previous usable fix, kept only to derive a speed when CoreLocation
    /// reports none.
    private var lastSpeedFix: CLLocation?
    /// Wall-clock moments for the ticker's check, which has no fix to read a
    /// timestamp from: when the slow stretch began, and when the last usable
    /// fix arrived.
    private var slowSeenAt: Date?
    private var lastFixSeenAt: Date?
    /// Whether the last usable fix said the runner was moving. A run through
    /// a tunnel goes quiet while moving and must not pause.
    private var lastFixWasMoving = false
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
    /// Best completed split so far; nil until one completes.
    var fastestSplitPace: Double? {
        splits.fastestPace(splitMeters: splitMeters, unit: unit, sport: sport)
    }
    /// Climb so far, by the same rule the saved activity and Apple Health use,
    /// so the number on the live screen is the number on the summary. Nil
    /// until two fixes with a real altitude have been accepted.
    var elevationGainMeters: Double? {
        SplitTimeline.elevationAscended(route: route)
    }
    /// The instant a stopwatch would have started to read `elapsed` right
    /// now; nil while paused. Stable for the whole recording segment, so a
    /// clock counting from it (the Live Activity's) needs no update per second.
    var elapsedAnchor: Date? {
        segmentStart.map { $0.addingTimeInterval(-accumulated) }
    }

    // MARK: Lifecycle

    func start(unit: DistanceUnit, sport: Sport = .run, autoPause: Bool = false) {
        guard state == .idle else { return }
        self.unit = unit
        self.sport = sport
        autoPauseEnabled = autoPause
        resetAutoPause()
        distanceMeters = 0
        elapsed = 0
        accumulated = 0
        route = []
        splits = [Split(index: 1, distanceMeters: 0, seconds: 0)]
        pauses = []
        nextMilestoneMeters = milestoneMeters
        lastAccepted = nil
        let t = now()
        startDate = t
        segmentStart = t
        state = .recording
        startTicker()
    }

    func pause() {
        isAutoPaused = false
        guard state == .recording, let seg = segmentStart else { return }
        accumulated += now().timeIntervalSince(seg)
        segmentStart = nil
        // The next fix after a resume must not add the distance covered while
        // paused, so the anchor is dropped here.
        lastAccepted = nil
        pauses.append(PauseInterval(start: now(), end: nil))
        state = .paused
        stopTicker()
        refreshElapsed()
    }

    func resume() {
        resetAutoPause()
        guard state == .paused else { return }
        let t = now()
        if let last = pauses.indices.last, pauses[last].end == nil {
            pauses[last].end = t
        }
        segmentStart = t
        state = .recording
        startTicker()
        refreshElapsed()
    }

    /// Stops the clock and hands back what was recorded, or nil when the run
    /// never moved. The recorder stays paused either way so the caller can
    /// offer Resume; call `discard()` once the summary is saved or dropped.
    func finish() -> RunSummary? {
        guard isActive else { return nil }
        // pause() also turns an automatic pause into a manual one, so the run
        // cannot restart itself behind the save sheet.
        pause()
        guard hasMovement, let startDate else { return nil }
        let end = now()
        return RunSummary(startDate: startDate,
                          endDate: end,
                          movingSeconds: elapsed,
                          distanceMeters: distanceMeters,
                          splitMeters: splitMeters,
                          route: route,
                          splits: splits,
                          sport: sport,
                          // finish() pauses first, so the trailing interval is
                          // still open. Closing it at the end date covers both
                          // cases: it is zero-length for a run stopped while
                          // recording, and the real gap for one stopped while
                          // already paused.
                          pauses: closedPauses(at: end))
    }

    /// Pauses with the trailing open interval closed off at `end`.
    private func closedPauses(at end: Date) -> [PauseInterval] {
        pauses.map { $0.end == nil ? PauseInterval(start: $0.start, end: max($0.start, end)) : $0 }
              .filter { $0.duration > 0 }
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
        pauses = []
        autoPauseEnabled = false
        resetAutoPause()
    }

    func refreshElapsed() {
        elapsed = accumulated + (segmentStart.map { now().timeIntervalSince($0) } ?? 0)
    }

    // MARK: Location

    func ingest(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= Self.maxHorizontalAccuracy else { return }
        if isAutoPaused {
            watchForResume(location)
            return
        }
        guard state == .recording, let seg = segmentStart else { return }
        if watchForPause(location) { return }
        // A cached fix from before this segment began would add ground we
        // never covered while recording.
        guard location.timestamp >= seg.addingTimeInterval(-1) else { return }

        guard let last = lastAccepted else {
            lastAccepted = location
            route.append(RoutePoint(location, cumulativeMeters: distanceMeters))
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
        route.append(RoutePoint(location, cumulativeMeters: distanceMeters))
        lastAccepted = location
        emitMilestones(step: step, seconds: seconds)
    }

    // MARK: Auto-pause

    /// Runs stop on a walk; walks and rides only when standing still. The
    /// resume speed sits above the pause speed so a pace hovering on the line
    /// does not flap. Run: pause under 1.7 m/s (about 15:47 /mi), resume at
    /// 1.85 m/s (about 14:30 /mi) — a brisk walk is 15-16 min/mi, the slowest
    /// jog about 14. Too high a resume speed would leave a slow jogger paused
    /// for good, which is worse than counting a fast walk.
    static func autoPauseSpeeds(for sport: Sport) -> (pauseBelow: CLLocationSpeed, resumeAt: CLLocationSpeed) {
        switch sport {
        case .run, .strollerRun: return (1.7, 1.85)
        case .walk: return (0.4, 0.7)
        case .bike: return (1.0, 1.8)
        }
    }
    /// How long the runner must stay slow before the clock stops, and fast
    /// before it restarts. One fix is not enough either way: GPS speed jumps
    /// at a crossing, a turn, a bad fix.
    static let autoPauseAfter: TimeInterval = 5
    static let autoResumeAfter: TimeInterval = 3
    /// No fix at all for this long, and the last one did not show movement:
    /// pause. A phone standing still can stop delivering fixes altogether.
    static let autoPauseQuietAfter: TimeInterval = 10

    private func resetAutoPause() {
        isAutoPaused = false
        slowSince = nil
        fastSince = nil
        lastSpeedFix = nil
        slowSeenAt = nil
        lastFixSeenAt = nil
        lastFixWasMoving = false
    }

    /// CoreLocation's Doppler speed when it has one, else the straight line
    /// from the previous usable fix. Nil when neither is available.
    private func speed(of location: CLLocation) -> CLLocationSpeed? {
        defer { lastSpeedFix = location }
        if location.speed >= 0 { return location.speed }
        guard let previous = lastSpeedFix else { return nil }
        let seconds = location.timestamp.timeIntervalSince(previous.timestamp)
        guard seconds > 0 else { return nil }
        return location.distance(from: previous) / seconds
    }

    /// While recording: stops the clock once the runner has been slow for
    /// `autoPauseAfter`. Returns true when it did, so the fix is not booked.
    private func watchForPause(_ location: CLLocation) -> Bool {
        guard autoPauseEnabled else { return false }
        lastFixSeenAt = now()
        guard let speed = speed(of: location) else {
            lastFixWasMoving = false
            return false
        }
        guard speed < Self.autoPauseSpeeds(for: sport).pauseBelow else {
            lastFixWasMoving = true
            slowSince = nil
            slowSeenAt = nil
            return false
        }
        lastFixWasMoving = false
        let since = slowSince ?? location.timestamp
        if slowSince == nil { slowSeenAt = now() }
        slowSince = since
        guard location.timestamp.timeIntervalSince(since) >= Self.autoPauseAfter else { return false }
        autoPause()
        return true
    }

    /// The ticker's half of the rule, for when the fixes stop coming: the
    /// slow stretch has gone on long enough, or nothing has said "moving"
    /// for `autoPauseQuietAfter`. Internal so tests can call it the way the
    /// ticker does, without waiting on a timer.
    func checkAutoPauseWithoutFixes() {
        guard autoPauseEnabled, state == .recording, !lastFixWasMoving else { return }
        let t = now()
        if let slowSeenAt, t.timeIntervalSince(slowSeenAt) >= Self.autoPauseAfter {
            autoPause()
        } else if let quietSince = lastFixSeenAt ?? segmentStart,
                  t.timeIntervalSince(quietSince) >= Self.autoPauseQuietAfter {
            autoPause()
        }
    }

    private func autoPause() {
        pause()
        isAutoPaused = true
        slowSince = nil
        slowSeenAt = nil
        fastSince = nil
        onAutoPauseChange?(true)
    }

    /// While auto-paused: restarts the clock once the runner has been back up
    /// to speed for `autoResumeAfter`, anchored at this fix so the next step
    /// counts.
    private func watchForResume(_ location: CLLocation) {
        guard let speed = speed(of: location) else { return }
        guard speed >= Self.autoPauseSpeeds(for: sport).resumeAt else {
            fastSince = nil
            return
        }
        let since = fastSince ?? location.timestamp
        fastSince = since
        guard location.timestamp.timeIntervalSince(since) >= Self.autoResumeAfter else { return }
        resume()
        lastAccepted = location
        route.append(RoutePoint(location, cumulativeMeters: distanceMeters))
        onAutoPauseChange?(false)
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
            Task { @MainActor [weak self] in
                self?.refreshElapsed()
                self?.checkAutoPauseWithoutFixes()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}

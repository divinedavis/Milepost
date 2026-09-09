import ActivityKit
import Foundation
import Observation

/// Mirrors the run in progress into a Live Activity so the Dynamic Island
/// and lock screen show the mile the runner is on. Starts the activity when
/// the recorder starts, updates it when something visible changes, ends it
/// when the run is saved or discarded.
///
/// Update budget: the clock ticks inside the widget on its own, and the
/// content state is rounded to what is displayed, so a 1 Hz poll only turns
/// into an update when the distance moves a hundredth of a unit, the split
/// rolls over, the pace changes by a second, or the run pauses / resumes.
/// A keep-alive update goes out at most once a minute so the activity does
/// not go stale while the runner waits at a light without pausing.
@MainActor
final class RunActivityController {
    static let pollInterval: TimeInterval = 1
    static let keepAlive: TimeInterval = 60
    /// If the app dies mid-run the activity greys out this long after the
    /// last update instead of showing a clock that keeps counting.
    static let staleAfter: TimeInterval = 120

    private let recorder: RunRecorder
    private var activity: ActivityKit.Activity<RunActivityAttributes>?
    private var lastState: RunActivityAttributes.ContentState?
    private var lastUpdate: Date = .distantPast
    private var ticker: Timer?
    private var wasActive = false

    init(recorder: RunRecorder) {
        self.recorder = recorder
        endStrayActivities()
        observeState()
    }

    // MARK: Recorder → activity

    /// Pure mapping, kept static so the unit tests can drive it with a
    /// recorder and a fake clock.
    static func state(for recorder: RunRecorder) -> RunActivityAttributes.ContentState {
        let unit = recorder.unit
        let split = recorder.currentSplit
        let fraction = split.map { min(1, max(0, $0.distanceMeters / recorder.splitMeters)) } ?? 0
        let clock: RunActivityAttributes.ContentState.Clock
        if recorder.state == .recording, let anchor = recorder.elapsedAnchor {
            clock = .running(since: anchor)
        } else {
            clock = .paused(elapsed: recorder.elapsed.rounded(.down))
        }
        return .init(distanceUnits: (recorder.distanceMeters / unit.meters * 100).rounded(.down) / 100,
                     clock: clock,
                     splitIndex: split?.index ?? 1,
                     splitFraction: (fraction * 100).rounded(.down) / 100,
                     splitPace: recorder.currentSplitPace.map { $0.rounded() },
                     previousSplitPace: recorder.previousSplitPace.map { $0.rounded() })
    }

    private func observeState() {
        withObservationTracking {
            _ = recorder.state
        } onChange: {
            Task { @MainActor [weak self] in
                self?.stateChanged()
                self?.observeState()
            }
        }
    }

    private func stateChanged() {
        let active = recorder.isActive
        switch (wasActive, active) {
        case (false, true):
            start()
            startTicker()
        case (true, false):
            stopTicker()
            end()
        default:
            // Pause / resume: push straight away rather than on the next tick.
            sync()
        }
        wasActive = active
    }

    private func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let startDate = recorder.startDate else { return }
        let attributes = RunActivityAttributes(unit: recorder.unit, sport: recorder.sport, startDate: startDate)
        let state = Self.state(for: recorder)
        do {
            activity = try ActivityKit.Activity.request(attributes: attributes,
                                            content: content(state),
                                            pushType: nil)
            lastState = state
            lastUpdate = Date()
        } catch {
            // Live Activities off in Settings, or the system's cap reached:
            // the run itself is unaffected.
            activity = nil
        }
    }

    private func sync(force: Bool = false) {
        guard let activity else { return }
        let state = Self.state(for: recorder)
        let due = Date().timeIntervalSince(lastUpdate) >= Self.keepAlive
        guard force || state != lastState || (due && !state.isPaused) else { return }
        lastState = state
        lastUpdate = Date()
        let content = content(state)
        Task { await activity.update(content) }
    }

    private func end() {
        guard let activity else { return }
        self.activity = nil
        lastState = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func content(_ state: RunActivityAttributes.ContentState) -> ActivityContent<RunActivityAttributes.ContentState> {
        // A paused run is allowed to sit on the lock screen indefinitely.
        ActivityContent(state: state,
                        staleDate: state.isPaused ? nil : Date().addingTimeInterval(Self.staleAfter))
    }

    /// The recorder lives in memory; a crash mid-run leaves an activity that
    /// belongs to nobody. Clear those on launch.
    private func endStrayActivities() {
        for stray in ActivityKit.Activity<RunActivityAttributes>.activities {
            Task { await stray.end(nil, dismissalPolicy: .immediate) }
        }
    }

    // MARK: Ticker

    private func startTicker() {
        stopTicker()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sync() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}

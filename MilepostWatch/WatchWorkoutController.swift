import CoreLocation
import Foundation
import HealthKit
import Observation

/// Records an activity on the watch.
///
/// Two engines run side by side and each does what it is good at:
///
/// - `HKWorkoutSession` owns the *session*. It is what keeps the app running
///   with the wrist down, puts the workout on the Smart Stack, and feeds heart
///   rate and active energy from the sensors. Nothing else on watchOS can do
///   any of that.
/// - `RunRecorder` — the same engine the phone uses, unchanged — owns
///   *distance, pace and splits* from GPS. Sharing it is the point: a mile
///   split on the watch is computed by exactly the same rules as one on the
///   phone, including the per-sport plausibility bounds and the stationary
///   gate, so the two never disagree about the same run.
///
/// Automatic distance collection is therefore switched off on the data source.
/// Leaving it on would have HealthKit's fused distance and Milepost's GPS
/// distance both writing to the same workout, and Health would show the sum.
@MainActor
@Observable
final class WatchWorkoutController: NSObject {
    enum Phase: Equatable { case idle, running, paused, ending, finished }

    let recorder: RunRecorder
    let location = WatchLocationService()

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    /// Fixes are handed to the route builder in batches; one call per GPS
    /// update would spend more time in IPC than in recording.
    private var pendingRouteLocations: [CLLocation] = []
    /// Pushes the run to the mirrored session on the phone. Two seconds is
    /// often enough that the phone's numbers never look stale, and rare enough
    /// that the channel is not the reason the battery goes flat.
    private var mirrorTicker: Timer?
    private static let mirrorInterval: TimeInterval = 2

    private(set) var phase: Phase = .idle
    private(set) var heartRate: Double?
    private(set) var averageHeartRate: Double?
    private(set) var maxHeartRate: Double?
    private(set) var activeKilocalories: Double?
    private(set) var errorText: String?
    /// Set once when a workout ends, for the summary screen and the phone sync.
    private(set) var finished: WatchActivityPayload?

    /// Mirrored from the iPhone's "Include route" switch, which starts off.
    /// The route is recorded either way — it travels to the phone with the
    /// activity — this only decides whether Health gets a copy.
    var includeRouteInHealth: Bool = HealthSettings.routeDefault
    /// Called when the phone ended the workout, so the watch still queues the
    /// activity for it rather than leaving it only in Health.
    var onRemoteEnd: (@MainActor (WatchActivityPayload) -> Void)?

    // The default cannot be written inline: `RunRecorder.init` is main-actor
    // isolated and a default argument is evaluated in a nonisolated context.
    init(recorder: RunRecorder? = nil) {
        self.recorder = recorder ?? RunRecorder()
        super.init()
        location.onUpdate = { [weak self] fix in
            guard let self else { return }
            self.recorder.ingest(fix)
            self.collectForRoute(fix)
        }
    }

    // MARK: Authorization

    static var isSupported: Bool { HKHealthStore.isHealthDataAvailable() }

    var shareTypes: Set<HKSampleType> {
        [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
        ]
    }

    var readTypes: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
        ]
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        guard Self.isSupported else { return false }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
            return false
        }
        return store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    // MARK: Lifecycle

    func start(sport: Sport, unit: DistanceUnit) async {
        guard phase == .idle, Self.isSupported else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = sport.workoutActivityType
        configuration.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            let dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            // See the note at the top of the file: GPS is the only distance.
            dataSource.disableCollection(for: HKQuantityType(.distanceWalkingRunning))
            dataSource.disableCollection(for: HKQuantityType(.distanceCycling))
            builder.dataSource = dataSource
            builder.delegate = self
            session.delegate = self

            self.session = session
            self.builder = builder
            routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())

            let startDate = Date()
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)

            recorder.start(unit: unit, sport: sport)
            location.startTracking()
            phase = .running
            errorText = nil

            // Lets the phone show and control this workout while it runs.
            try? await session.startMirroringToCompanionDevice()
            startMirrorTicker()
        } catch {
            errorText = error.localizedDescription
            cleanUp()
        }
    }

    func pause() {
        guard phase == .running else { return }
        session?.pause()
        recorder.pause()
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        session?.resume()
        recorder.resume()
        phase = .running
    }

    func toggle() {
        switch phase {
        case .running: pause()
        case .paused: resume()
        default: break
        }
    }

    /// Stops recording and saves the workout. Returns the payload for the
    /// phone, or nil if the activity never moved far enough to count.
    @discardableResult
    func end(title: String? = nil) async -> WatchActivityPayload? {
        guard phase == .running || phase == .paused else { return nil }
        phase = .ending
        location.stopTracking()

        let summary = recorder.finish()
        let endDate = Date()

        guard let session, let builder else {
            cleanUp()
            return nil
        }

        session.end()

        var workoutID: String?
        do {
            if let summary {
                let samples = distanceSamples(for: summary)
                if !samples.isEmpty { try await builder.addSamples(samples) }
                let events = lapEvents(for: summary)
                if !events.isEmpty { try await builder.addWorkoutEvents(events) }
                try await builder.addMetadata(metadata(for: summary))
            }
            try await builder.endCollection(at: endDate)
            let workout = try await builder.finishWorkout()
            if let workout {
                workoutID = workout.uuid.uuidString
                await attachRoute(to: workout)
            }
        } catch {
            errorText = error.localizedDescription
        }

        guard let summary else {
            cleanUp()
            phase = .idle
            recorder.discard()
            return nil
        }

        let payload = WatchActivityPayload(title: title ?? Format.defaultTitle(for: summary.startDate, sport: summary.sport),
                                           summary: summary,
                                           averageHeartRate: averageHeartRate,
                                           maxHeartRate: maxHeartRate,
                                           activeKilocalories: activeKilocalories,
                                           healthWorkoutID: workoutID)
        finished = payload
        phase = .finished
        cleanUp()
        return payload
    }

    /// Throws the recording away without saving anything. The workout builder
    /// is discarded too, or Health would keep a zero-distance stub.
    func discard() {
        session?.end()
        builder?.discardWorkout()
        location.stopTracking()
        recorder.discard()
        cleanUp()
        phase = .idle
        finished = nil
    }

    func clearFinished() {
        finished = nil
        phase = .idle
        recorder.discard()
        resetMetrics()
    }

    private func cleanUp() {
        stopMirrorTicker()
        session = nil
        builder = nil
        routeBuilder = nil
        pendingRouteLocations = []
    }

    private func resetMetrics() {
        heartRate = nil
        averageHeartRate = nil
        maxHeartRate = nil
        activeKilocalories = nil
    }

    // MARK: Mirroring

    private func startMirrorTicker() {
        stopMirrorTicker()
        let timer = Timer(timeInterval: Self.mirrorInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pushStateToPhone() }
        }
        RunLoop.main.add(timer, forMode: .common)
        mirrorTicker = timer
    }

    private func stopMirrorTicker() {
        mirrorTicker?.invalidate()
        mirrorTicker = nil
    }

    private func pushStateToPhone() {
        guard let session, phase == .running || phase == .paused else { return }
        recorder.refreshElapsed()
        let snapshot = MirroredWorkoutState(sportRaw: recorder.sport.rawValue,
                                            unitRaw: recorder.unit.rawValue,
                                            distanceMeters: recorder.distanceMeters,
                                            elapsed: recorder.elapsed,
                                            paceSecondsPerUnit: recorder.currentSplitPace ?? recorder.averagePace,
                                            heartRate: heartRate,
                                            activeKilocalories: activeKilocalories,
                                            isPaused: phase == .paused,
                                            elapsedAnchor: recorder.elapsedAnchor)
        let data = WorkoutRemoteMessage.state(snapshot).data
        Task {
            // Out of range is expected and is not worth surfacing: the watch is
            // the recorder and carries on regardless.
            try? await session.sendToRemoteWorkoutSession(data: data)
        }
    }

    // MARK: Route

    private func collectForRoute(_ fix: CLLocation) {
        guard includeRouteInHealth, recorder.state == .recording,
              fix.horizontalAccuracy > 0,
              fix.horizontalAccuracy <= RunRecorder.maxHorizontalAccuracy else { return }
        pendingRouteLocations.append(fix)
        guard pendingRouteLocations.count >= 10 else { return }
        flushRouteLocations()
    }

    private func flushRouteLocations() {
        guard let routeBuilder, !pendingRouteLocations.isEmpty else { return }
        let batch = pendingRouteLocations
        pendingRouteLocations = []
        Task {
            do { try await routeBuilder.insertRouteData(batch) }
            catch { self.errorText = error.localizedDescription }
        }
    }

    private func attachRoute(to workout: HKWorkout) async {
        guard includeRouteInHealth, let routeBuilder else { return }
        if !pendingRouteLocations.isEmpty {
            let batch = pendingRouteLocations
            pendingRouteLocations = []
            try? await routeBuilder.insertRouteData(batch)
        }
        // This route builder was made standalone rather than taken off the
        // workout builder, so it is finished by hand here.
        _ = try? await routeBuilder.finishRoute(with: workout, metadata: nil)
    }

    // MARK: Samples

    private func distanceSamples(for summary: RunSummary) -> [HKQuantitySample] {
        guard summary.distanceMeters > 0 else { return [] }
        return [HKQuantitySample(type: summary.sport.distanceQuantityType,
                                 quantity: HKQuantity(unit: .meter(), doubleValue: summary.distanceMeters),
                                 start: summary.startDate,
                                 end: summary.endDate,
                                 device: .local(),
                                 metadata: nil)]
    }

    private func lapEvents(for summary: RunSummary) -> [HKWorkoutEvent] {
        let ranges = SplitTimeline.ranges(splits: summary.splits,
                                          splitMeters: summary.splitMeters,
                                          route: summary.route,
                                          startDate: summary.startDate,
                                          endDate: summary.endDate)
        return ranges
            .filter { $0.split.isComplete(splitMeters: summary.splitMeters) }
            .map { HKWorkoutEvent(type: .lap, dateInterval: DateInterval(start: $0.start, end: $0.end), metadata: nil) }
    }

    private func metadata(for summary: RunSummary) -> [String: Any] {
        var metadata: [String: Any] = [
            HKMetadataKeyIndoorWorkout: false,
            HKMetadataKeyWorkoutBrandName: "Milepost",
        ]
        metadata.merge(summary.sport.healthBrandMetadata) { _, new in new }
        if let ascended = SplitTimeline.elevationAscended(route: summary.route) {
            metadata[HKMetadataKeyElevationAscended] = HKQuantity(unit: .meter(), doubleValue: ascended)
        }
        if let descended = SplitTimeline.elevationDescended(route: summary.route) {
            metadata[HKMetadataKeyElevationDescended] = HKQuantity(unit: .meter(), doubleValue: descended)
        }
        metadata[HKMetadataKeyTimeZone] = TimeZone.current.identifier
        return metadata
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutController: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {
        Task { @MainActor in
            // The session can be paused or resumed from the phone or by the
            // system (a call, wrist-down auto-pause), so the recorder follows
            // the session rather than the other way round.
            switch toState {
            case .running where self.phase == .paused:
                self.recorder.resume()
                self.phase = .running
            case .paused where self.phase == .running:
                self.recorder.pause()
                self.phase = .paused
            default:
                break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.errorText = error.localizedDescription
            self.location.stopTracking()
            self.phase = .idle
        }
    }

    /// Pause / Resume / End sent from the phone's mirrored session.
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        Task { @MainActor in
            for packet in data {
                guard case let .command(command)? = WorkoutRemoteMessage.decode(packet) else { continue }
                switch command {
                case .pause: self.pause()
                case .resume: self.resume()
                case .end:
                    if let payload = await self.end() {
                        self.onRemoteEnd?(payload)
                    }
                }
            }
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutController: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in
            let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
            for type in collectedTypes {
                guard let quantityType = type as? HKQuantityType,
                      let statistics = workoutBuilder.statistics(for: quantityType) else { continue }
                switch quantityType {
                case HKQuantityType(.heartRate):
                    self.heartRate = statistics.mostRecentQuantity()?.doubleValue(for: beatsPerMinute)
                    self.averageHeartRate = statistics.averageQuantity()?.doubleValue(for: beatsPerMinute)
                    self.maxHeartRate = statistics.maximumQuantity()?.doubleValue(for: beatsPerMinute)
                case HKQuantityType(.activeEnergyBurned):
                    self.activeKilocalories = statistics.sumQuantity()?.doubleValue(for: .kilocalorie())
                default:
                    break
                }
            }
        }
    }
}

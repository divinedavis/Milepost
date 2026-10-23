import CoreLocation
import Foundation
import HealthKit
import Observation

/// What Health knows about an activity that Milepost could not measure itself.
/// Every field is optional: a phone-only run has none of them, and a run with
/// a Watch on the wrist has most.
struct HealthMetrics: Equatable {
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var activeKilocalories: Double?
    var stepCount: Double?
    var averageRunningPower: Double?
    var averageStrideLengthMeters: Double?
    var averageCyclingPower: Double?
    var averageCyclingCadence: Double?
    /// Who measured the heart rate — "Oura", a Watch's name, a strap's app —
    /// so a ring's minute-by-minute readings are not mistaken for a Watch's.
    var heartRateSource: String?

    var isEmpty: Bool {
        averageHeartRate == nil && maxHeartRate == nil && activeKilocalories == nil
            && stepCount == nil && averageRunningPower == nil && averageStrideLengthMeters == nil
            && averageCyclingPower == nil && averageCyclingCadence == nil
    }

    /// "Oura", or "Oura and Jo's Apple Watch" when two things were measuring.
    /// Health reports one source per app or device, in no fixed order.
    static func sourceLabel(_ names: [String]) -> String? {
        let unique = Array(Set(names.filter { !$0.isEmpty })).sorted()
        guard !unique.isEmpty else { return nil }
        return ListFormatter.localizedString(byJoining: unique)
    }
}

/// One calendar day of walking as Health counts it: the iPhone's motion
/// chip and an Apple Watch both write steps, and Health merges them so a
/// step counted by both is counted once. Nil means Health had nothing (or
/// read access was refused — Health will not say which).
struct DailyMovement: Equatable, Identifiable {
    var day: Date
    var steps: Double?
    var distanceMeters: Double?

    var id: Date { day }

    /// Newest first, one entry per day from `days - 1` days ago to today,
    /// filling days Health had nothing for with nils so the list never has
    /// holes.
    static func days(_ days: Int, endingOn now: Date, calendar: Calendar = .current,
                     steps: [Date: Double], distance: [Date: Double]) -> [DailyMovement] {
        let today = calendar.startOfDay(for: now)
        return (0..<max(0, days)).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return DailyMovement(day: day, steps: steps[day], distanceMeters: distance[day])
        }
    }
}

/// Everything Milepost does with Apple Health: writing a finished activity in
/// as a real workout, and reading back the things a wrist can measure and a
/// phone in a pocket cannot.
///
/// Writing is off until the user turns it on, and the route is a second,
/// separate switch — see `HealthSettings`.
@MainActor
@Observable
final class HealthKitService {
    enum HealthError: LocalizedError {
        case unavailable
        case notAuthorized

        var errorDescription: String? {
            switch self {
            case .unavailable: return "Apple Health is not available on this device."
            case .notAuthorized: return "Milepost is not allowed to add workouts to Apple Health. Turn it on in Health > Sharing > Apps."
            }
        }
    }

    /// iPad and the simulator's older runtimes have no Health database. Every
    /// entry point checks this rather than letting HKHealthStore throw.
    static let isSupported = HKHealthStore.isHealthDataAvailable()

    private let store = HKHealthStore()

    private(set) var lastError: String?
    /// Other apps' workout routes for "Your map" (`HealthSettings.mapKey`).
    private(set) var mapRoutes: [HealthRoute] = []
    private var mapRoutesLoadedAt: Date?

    // MARK: Types

    /// Written by Milepost. Route is included unconditionally so the user is
    /// asked once; whether a route is actually written is the app's setting,
    /// not a permission we re-request later.
    /// Nothing is asked for that is not written. An effort score, for example,
    /// would be a good fit for this app but nothing produces one yet, and
    /// asking for a permission the app never uses is how a Health sheet ends up
    /// looking like a data grab.
    static var shareTypes: Set<HKSampleType> {
        [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.activeEnergyBurned),
        ]
    }

    /// Read back onto the activity detail screen, plus the body mass the
    /// calorie estimate needs. Health never reports whether a read was
    /// granted, so a denied type simply returns nothing.
    static var readTypes: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.stepCount),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.bodyMass),
            HKQuantityType(.runningPower),
            HKQuantityType(.runningStrideLength),
            HKQuantityType(.cyclingPower),
            HKQuantityType(.cyclingCadence),
        ]
    }

    // MARK: Authorization

    /// `.sharingAuthorized` only ever means "the user said yes to workouts".
    /// Health deliberately refuses to say whether reads were granted.
    var canWriteWorkouts: Bool {
        guard Self.isSupported else { return false }
        return store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    var hasBeenAsked: Bool {
        guard Self.isSupported else { return false }
        return store.authorizationStatus(for: HKObjectType.workoutType()) != .notDetermined
    }

    /// Shows the Health sheet if it has not been shown. Returns whether
    /// Milepost may now write workouts.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard Self.isSupported else {
            lastError = HealthError.unavailable.errorDescription
            return false
        }
        do {
            try await store.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        return canWriteWorkouts
    }

    /// Just the two the daily steps card reads. Asked on their own, so
    /// turning on daily steps never asks to write workouts.
    static var dailyReadTypes: Set<HKObjectType> {
        [HKQuantityType(.stepCount), HKQuantityType(.distanceWalkingRunning)]
    }

    func requestDailyMovementAccess() async {
        guard Self.isSupported else {
            lastError = HealthError.unavailable.errorDescription
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: Self.dailyReadTypes)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Workouts and their routes, read only, for "Show Apple Health
    /// workouts on my map". Asked on their own, on that switch's tap.
    static var mapReadTypes: Set<HKObjectType> {
        [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
    }

    func requestMapAccess() async {
        guard Self.isSupported else {
            lastError = HealthError.unavailable.errorDescription
            return
        }
        do {
            try await store.requestAuthorization(toShare: [], read: Self.mapReadTypes)
        } catch {
            lastError = error.localizedDescription
        }
        await refreshMapRoutes(force: true)
    }

    // MARK: Writing

    /// Writes a finished activity into Health as a workout, and returns its
    /// Health UUID.
    ///
    /// The workout carries the same moving time Milepost shows (pauses go in
    /// as pause/resume events, which is what Health subtracts), each completed
    /// split as a lap, distance under the type for the sport, and estimated
    /// active energy. The route is written only when `includeRoute` is true.
    @discardableResult
    func save(summary: RunSummary,
              title: String,
              activityID: UUID,
              includeRoute: Bool) async throws -> UUID {
        guard Self.isSupported else { throw HealthError.unavailable }
        guard canWriteWorkouts else { throw HealthError.notAuthorized }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = summary.sport.workoutActivityType
        configuration.locationType = .outdoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: summary.startDate)
            try await builder.addMetadata(metadata(for: summary, title: title, activityID: activityID))

            let samples = quantitySamples(for: summary)
            if !samples.isEmpty {
                try await builder.addSamples(samples)
            }

            let events = workoutEvents(for: summary)
            if !events.isEmpty {
                try await builder.addWorkoutEvents(events)
            }

            // The route builder must be taken from the workout builder, not
            // made standalone: the workout builder finishes the route itself
            // and finishing it by hand here would orphan it.
            if includeRoute, !summary.route.isEmpty,
               let routeBuilder = builder.seriesBuilder(for: HKSeriesType.workoutRoute()) as? HKWorkoutRouteBuilder {
                let locations = summary.route.map(\.location).filter { $0.horizontalAccuracy > 0 }
                if !locations.isEmpty {
                    try await routeBuilder.insertRouteData(locations)
                }
            }

            try await builder.endCollection(at: summary.endDate)
            guard let workout = try await builder.finishWorkout() else {
                throw HealthError.notAuthorized
            }
            lastError = nil
            return workout.uuid
        } catch {
            // A half-built workout left behind would show up in Health as a
            // zero-distance stub on the next launch.
            builder.discardWorkout()
            lastError = error.localizedDescription
            throw error
        }
    }

    /// Removes a workout Milepost wrote. Health only lets an app delete its
    /// own samples, so a workout the user logged elsewhere is left alone.
    func deleteWorkout(id: UUID) async {
        guard Self.isSupported, canWriteWorkouts else { return }
        let predicate = HKQuery.predicateForObject(with: id)
        do {
            let workouts = try await samples(of: HKObjectType.workoutType(), predicate: predicate, limit: 1)
            guard let workout = workouts.first else { return }
            try await store.delete(workout)
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func metadata(for summary: RunSummary, title: String, activityID: UUID) -> [String: Any] {
        var metadata: [String: Any] = [
            HKMetadataKeyIndoorWorkout: false,
            // Lets Milepost recognise its own workouts later, and stops a
            // re-save from creating a duplicate the user has to clean up.
            HKMetadataKeyExternalUUID: activityID.uuidString,
            HKMetadataKeyWorkoutBrandName: "Milepost",
            HKMetadataKeyGroupFitness: false,
        ]
        metadata.merge(summary.sport.healthBrandMetadata) { _, new in new }

        if let ascended = SplitTimeline.elevationAscended(route: summary.route) {
            metadata[HKMetadataKeyElevationAscended] = HKQuantity(unit: .meter(), doubleValue: ascended)
        }
        if let descended = SplitTimeline.elevationDescended(route: summary.route) {
            metadata[HKMetadataKeyElevationDescended] = HKQuantity(unit: .meter(), doubleValue: descended)
        }
        if summary.movingSeconds > 0 {
            let speed = summary.distanceMeters / summary.movingSeconds
            metadata[HKMetadataKeyAverageSpeed] = HKQuantity(unit: .meter().unitDivided(by: .second()),
                                                            doubleValue: speed)
            let mets = CalorieEstimator.metabolicEquivalent(sport: summary.sport, metersPerSecond: speed)
            metadata[HKMetadataKeyAverageMETs] = HKQuantity(unit: HKUnit.kilocalorie().unitDivided(by: .hour().unitMultiplied(by: .gramUnit(with: .kilo))),
                                                            doubleValue: mets)
        }
        if let fastest = summary.route.compactMap(\.speed).filter({ $0 >= 0 }).max() {
            metadata[HKMetadataKeyMaximumSpeed] = HKQuantity(unit: .meter().unitDivided(by: .second()),
                                                            doubleValue: fastest)
        }
        metadata[HKMetadataKeyTimeZone] = TimeZone.current.identifier
        return metadata
    }

    private func quantitySamples(for summary: RunSummary) -> [HKQuantitySample] {
        var samples: [HKQuantitySample] = []
        let device = HKDevice.local()

        if summary.distanceMeters > 0 {
            samples.append(HKQuantitySample(type: summary.sport.distanceQuantityType,
                                            quantity: HKQuantity(unit: .meter(), doubleValue: summary.distanceMeters),
                                            start: summary.startDate,
                                            end: summary.endDate,
                                            device: device,
                                            metadata: nil))
        }

        // Health prefers a heart-rate-derived figure when a Watch supplied one;
        // this estimate is what a pocketed phone can offer instead, and the UI
        // never presents it as measured.
        if let kilocalories = CalorieEstimator.activeKilocalories(sport: summary.sport,
                                                                 distanceMeters: summary.distanceMeters,
                                                                 movingSeconds: summary.movingSeconds,
                                                                 bodyMassKilograms: cachedBodyMassKilograms ?? CalorieEstimator.defaultBodyMassKilograms),
           kilocalories > 0 {
            samples.append(HKQuantitySample(type: HKQuantityType(.activeEnergyBurned),
                                            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kilocalories),
                                            start: summary.startDate,
                                            end: summary.endDate,
                                            device: device,
                                            metadata: [HKMetadataKeyWasUserEntered: false]))
        }
        return samples
    }

    /// Pause/resume pairs, plus a lap for every split that ran its full
    /// distance. Health derives the workout's duration from the pauses, so
    /// leaving them out would show elapsed time where Milepost shows moving
    /// time.
    private func workoutEvents(for summary: RunSummary) -> [HKWorkoutEvent] {
        var events: [HKWorkoutEvent] = []
        for pause in summary.pauses {
            guard let end = pause.end, end > pause.start else { continue }
            events.append(HKWorkoutEvent(type: .pause,
                                         dateInterval: DateInterval(start: pause.start, duration: 0),
                                         metadata: nil))
            events.append(HKWorkoutEvent(type: .resume,
                                         dateInterval: DateInterval(start: end, duration: 0),
                                         metadata: nil))
        }

        let ranges = SplitTimeline.ranges(splits: summary.splits,
                                          splitMeters: summary.splitMeters,
                                          route: summary.route,
                                          startDate: summary.startDate,
                                          endDate: summary.endDate)
        for dated in ranges where dated.split.isComplete(splitMeters: summary.splitMeters) {
            events.append(HKWorkoutEvent(type: .lap,
                                         dateInterval: DateInterval(start: dated.start, end: dated.end),
                                         metadata: nil))
        }
        return events.sorted { $0.dateInterval.start < $1.dateInterval.start }
    }

    // MARK: Reading

    private var cachedBodyMassKilograms: Double?

    /// The user's weight, for the calorie estimate. Cached for the session:
    /// it moves by the week, not by the run, and the estimate scales linearly
    /// with it so a day-old value costs nothing.
    @discardableResult
    func refreshBodyMass() async -> Double? {
        guard Self.isSupported else { return nil }
        let value = await mostRecentQuantity(HKQuantityType(.bodyMass))?.doubleValue(for: .gramUnit(with: .kilo))
        if let value, value > 0 { cachedBodyMassKilograms = value }
        return cachedBodyMassKilograms
    }

    /// Whatever Health holds for the window this activity covers — heart rate
    /// from a Watch, strap or Oura ring, real active energy, running or cycling form.
    /// Queried by date range rather than against a stored workout so that a
    /// run Milepost recorded on the phone still picks up the Watch's heart
    /// rate, whoever wrote the workout.
    func metrics(start: Date, end: Date, sport: Sport) async -> HealthMetrics {
        guard Self.isSupported, end > start else { return HealthMetrics() }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        var metrics = HealthMetrics()
        let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())
        metrics.averageHeartRate = await statistic(HKQuantityType(.heartRate), predicate, .discreteAverage)?
            .averageQuantity()?.doubleValue(for: beatsPerMinute)
        metrics.maxHeartRate = await statistic(HKQuantityType(.heartRate), predicate, .discreteMax)?
            .maximumQuantity()?.doubleValue(for: beatsPerMinute)
        if metrics.averageHeartRate != nil {
            metrics.heartRateSource = HealthMetrics.sourceLabel(await sourceNames(HKQuantityType(.heartRate), predicate))
        }
        metrics.activeKilocalories = await statistic(HKQuantityType(.activeEnergyBurned), predicate, .cumulativeSum)?
            .sumQuantity()?.doubleValue(for: .kilocalorie())

        switch sport {
        case .run, .strollerRun, .walk:
            metrics.stepCount = await statistic(HKQuantityType(.stepCount), predicate, .cumulativeSum)?
                .sumQuantity()?.doubleValue(for: .count())
            metrics.averageRunningPower = await statistic(HKQuantityType(.runningPower), predicate, .discreteAverage)?
                .averageQuantity()?.doubleValue(for: .watt())
            metrics.averageStrideLengthMeters = await statistic(HKQuantityType(.runningStrideLength), predicate, .discreteAverage)?
                .averageQuantity()?.doubleValue(for: .meter())
        case .bike:
            metrics.averageCyclingPower = await statistic(HKQuantityType(.cyclingPower), predicate, .discreteAverage)?
                .averageQuantity()?.doubleValue(for: .watt())
            metrics.averageCyclingCadence = await statistic(HKQuantityType(.cyclingCadence), predicate, .discreteAverage)?
                .averageQuantity()?.doubleValue(for: .count().unitDivided(by: .minute()))
        }
        return metrics
    }

    /// Steps and walking + running distance per day for the last `days`
    /// days, newest first. A statistics collection query, so Health merges the
    /// phone's and the watch's samples instead of adding them up.
    func dailyMovement(days: Int, now: Date = .now) async -> [DailyMovement] {
        guard Self.isSupported, days > 0 else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        let steps = await dailySums(HKQuantityType(.stepCount), unit: .count(), from: start, to: now)
        let distance = await dailySums(HKQuantityType(.distanceWalkingRunning), unit: .meter(), from: start, to: now)
        return DailyMovement.days(days, endingOn: now, calendar: calendar, steps: steps, distance: distance)
    }

    /// Loads other apps' walks, runs and rides with a route from the last
    /// year into `mapRoutes`, at most every `refreshSeconds`. Off, it empties.
    func refreshMapRoutes(force: Bool = false, now: Date = .now) async {
        guard UserDefaults.standard.bool(forKey: HealthSettings.mapKey) else {
            mapRoutes = []
            mapRoutesLoadedAt = nil
            return
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitest-health-routes") {
            mapRoutes = HealthRouteRules.demo(now: now)
            return
        }
        #endif
        if !force, let loaded = mapRoutesLoadedAt,
           now.timeIntervalSince(loaded) < HealthRouteRules.refreshSeconds { return }
        guard Self.isSupported else { return }
        mapRoutesLoadedAt = now
        mapRoutes = await workoutRoutes(since: now.addingTimeInterval(-Double(HealthRouteRules.windowDays) * 86_400))
    }

    private func workoutRoutes(since start: Date) async -> [HealthRoute] {
        let kinds = NSCompoundPredicate(orPredicateWithSubpredicates:
            HealthRouteRules.workoutTypes.map { HKQuery.predicateForWorkouts(with: $0) })
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates:
            [kinds, HKQuery.predicateForSamples(withStart: start, end: nil)])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        let workouts: [HKWorkout] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                      limit: HealthRouteRules.maxWorkouts, sortDescriptors: sort) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }
        var routes: [HealthRoute] = []
        for workout in workouts {
            // Milepost's own (phone and watch) are activities already.
            if workout.sourceRevision.source.bundleIdentifier.hasPrefix("com.divinedavis.milepost") { continue }
            guard let sport = HealthRouteRules.sport(for: workout.workoutActivityType) else { continue }
            let coordinates = await routeCoordinates(of: workout)
            guard coordinates.count > 1 else { continue }
            routes.append(HealthRoute(id: workout.uuid, sport: sport, start: workout.startDate,
                                      externalID: workout.metadata?[HKMetadataKeyExternalUUID] as? String,
                                      brand: workout.metadata?[HKMetadataKeyWorkoutBrandName] as? String,
                                      coordinates: RouteLine.thin(coordinates, to: RouteLine.maxPoints)))
        }
        return routes
    }

    /// Every location of every route on the workout (a paused workout can
    /// carry more than one), in order. Empty when there is none or reading
    /// routes was refused.
    private func routeCoordinates(of workout: HKWorkout) async -> [CLLocationCoordinate2D] {
        let routes = (try? await samples(of: HKSeriesType.workoutRoute(),
                                         predicate: HKQuery.predicateForObjects(from: workout),
                                         limit: HKObjectQueryNoLimit))?
            .compactMap { $0 as? HKWorkoutRoute } ?? []
        var coordinates: [CLLocationCoordinate2D] = []
        for route in routes {
            coordinates += await withCheckedContinuation { continuation in
                let collected = LocationBatch()
                let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                    collected.coordinates += (locations ?? []).map(\.coordinate)
                    if done || error != nil { continuation.resume(returning: collected.coordinates) }
                }
                store.execute(query)
            }
        }
        return coordinates
    }

    // MARK: Query plumbing

    private func dailySums(_ type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date) async -> [Date: Double] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: type,
                                                    quantitySamplePredicate: predicate,
                                                    options: .cumulativeSum,
                                                    anchorDate: start,
                                                    intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, _ in
                var sums: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    if let value = statistics.sumQuantity()?.doubleValue(for: unit) {
                        sums[Calendar.current.startOfDay(for: statistics.startDate)] = value
                    }
                }
                continuation.resume(returning: sums)
            }
            store.execute(query)
        }
    }

    private func statistic(_ type: HKQuantityType,
                           _ predicate: NSPredicate,
                           _ options: HKStatisticsOptions) async -> HKStatistics? {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: options) { _, statistics, _ in
                continuation.resume(returning: statistics)
            }
            store.execute(query)
        }
    }

    private func sourceNames(_ type: HKSampleType, _ predicate: NSPredicate) async -> [String] {
        await withCheckedContinuation { continuation in
            let query = HKSourceQuery(sampleType: type, samplePredicate: predicate) { _, sources, _ in
                continuation.resume(returning: sources.map { $0.map(\.name) } ?? [])
            }
            store.execute(query)
        }
    }

    private func mostRecentQuantity(_ type: HKQuantityType) async -> HKQuantity? {
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: sort) { _, samples, _ in
                continuation.resume(returning: (samples?.first as? HKQuantitySample)?.quantity)
            }
            store.execute(query)
        }
    }

    private func samples(of type: HKSampleType, predicate: NSPredicate, limit: Int) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: nil) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }
}

/// Collects a route query's batches; the handler is called once per batch.
private final class LocationBatch: @unchecked Sendable {
    var coordinates: [CLLocationCoordinate2D] = []
}

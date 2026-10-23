import SwiftData
import SwiftUI

@main
struct MilepostApp: App {
    @State private var location: LocationService
    @State private var recorder: RunRecorder
    @State private var announcer: VoiceAnnouncer
    /// Not observed by any view; held so the Live Activity stays wired for
    /// the life of the process.
    @State private var liveActivity: RunActivityController
    @State private var social: SocialStore
    @State private var health = HealthKitService()
    @State private var watchSync: PhoneWatchSync
    @State private var mirror = MirroredWorkoutMonitor()
    @State private var celebration = SaveCelebration()
    @State private var recovery = RunRecovery()
    @State private var holiday = HolidayStore()
    /// Held for the life of the process: its timer writes the run in progress.
    @State private var autosave: RunAutosave
    /// A run rescued from the last process, still to be shared / written to
    /// Health once the app is up (both are async).
    @State private var recoveredActivity: Activity?
    @Environment(\.scenePhase) private var scenePhase
    /// Cold launches only: both are set once per process, so coming back from
    /// the background never replays the splash. The app itself mounts only
    /// when the splash says so (see `LaunchSplashView.onReveal`).
    @State private var splash = LaunchSplashView.isEnabled
    @State private var appMounted = !LaunchSplashView.isEnabled

    let container: ModelContainer

    init() {
        let isUITest = ProcessInfo.processInfo.arguments.contains("-uitest")
        if isUITest, let bundle = Bundle.main.bundleIdentifier {
            // Settings must not leak from one UI run into the next (an aborted
            // test once left voice cues on and broke the following run).
            UserDefaults.standard.removePersistentDomain(forName: bundle)
        }
        // Lets the Health section be driven without tapping the toggle that
        // raises Apple's permission sheet, which the runner cannot dismiss.
        if isUITest, ProcessInfo.processInfo.arguments.contains("-uitest-health-on") {
            UserDefaults.standard.set(true, forKey: HealthSettings.enabledKey)
        }
        if isUITest, ProcessInfo.processInfo.arguments.contains("-uitest-daily-demo") {
            UserDefaults.standard.set(true, forKey: HealthSettings.dailyKey)
        }
        if isUITest, ProcessInfo.processInfo.arguments.contains("-uitest-health-routes") {
            UserDefaults.standard.set(true, forKey: HealthSettings.mapKey)
        }
        let location = LocationService()
        let recorder = RunRecorder()
        let announcer = VoiceAnnouncer(isMuted: isUITest)
        location.onUpdate = { recorder.ingest($0) }
        recorder.onMilestone = { announcer.announce($0) }
        _location = State(initialValue: location)
        _recorder = State(initialValue: recorder)
        _announcer = State(initialValue: announcer)
        _liveActivity = State(initialValue: RunActivityController(recorder: recorder))
        // What the Pause / Resume button on the Live Activity calls. The
        // system runs that intent in this process, so the recorder it reaches
        // is the one actually recording.
        RunActivityActions.toggleRecording = { [weak recorder] in
            guard let recorder else { return }
            switch recorder.state {
            case .recording: recorder.pause()
            case .paused: recorder.resume()
            case .idle: break
            }
        }

        let config = ModelConfiguration(isStoredInMemoryOnly: isUITest)
        do {
            container = try ModelContainer(for: Activity.self, configurations: config)
        } catch {
            // A corrupt store on disk should not brick the app; start clean.
            container = try! ModelContainer(for: Activity.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        // A run the last process was recording when it died (battery, crash,
        // killed by iOS) is saved before anything can start a new one.
        // UI tests get their own file, wiped here: many of them start a run
        // and terminate the app, which must not seed the next test's store.
        // Next to the real one, not in tmp: iOS may empty tmp between two
        // launches, which made the kill-and-relaunch test fail only in the
        // full ship run (2026-10-22).
        let autosaveURL = isUITest
            ? RunAutosave.defaultURL.deletingLastPathComponent().appendingPathComponent("uitest-run-in-progress.json")
            : RunAutosave.defaultURL
        // `-uitest-keep-autosave` is the relaunch after a test killed the app
        // mid-run: the file is the thing under test.
        if isUITest, !ProcessInfo.processInfo.arguments.contains("-uitest-keep-autosave") {
            try? FileManager.default.removeItem(at: autosaveURL)
        }
        let autosave = RunAutosave(recorder: recorder, fileURL: autosaveURL)
        #if DEBUG
        if isUITest, ProcessInfo.processInfo.arguments.contains("-uitest-seed-checkpoint") {
            autosave.write(HeatmapPreviewData.interruptedWalk())
            autosave.flush()
        }
        #endif
        let recovery = RunRecovery()
        _recoveredActivity = State(initialValue: recovery.recover(from: autosave, into: container.mainContext))
        _recovery = State(initialValue: recovery)
        autosave.start()
        _autosave = State(initialValue: autosave)

        // MetricKit: launch/hang/memory summaries and crash diagnostics, logged
        // on device only. ship.sh fails if this line goes.
        MetricsReporter.shared.start()

        #if DEBUG
        // Past activities for the Record map's heatmap, so it can be driven
        // and captured on an in-memory store.
        if isUITest, ProcessInfo.processInfo.arguments.contains("-uitest-seed-heatmap") {
            HeatmapPreviewData.seed(into: container.mainContext)
        }
        #endif

        let social = SocialStore(backend: Self.socialBackend(isUITest: isUITest))
        let context = container.mainContext
        social.localActivities = { (try? context.fetch(FetchDescriptor<Activity>())) ?? [] }
        _social = State(initialValue: social)

        // Activities recorded on the Apple Watch arrive here, usually while
        // the app is in the background.
        let watchSync = PhoneWatchSync()
        watchSync.onReceive = { payload in
            guard let activity = WatchActivityImporter.store(payload, in: context) else { return }
            Task { await social.share(activity) }
        }
        _watchSync = State(initialValue: watchSync)
    }

    /// Under `-uitest` the session is in memory (the runner cannot write the
    /// keychain); `-uitest-social-demo` swaps in canned friends so signed-in
    /// screens can be driven at all.
    private static func socialBackend(isUITest: Bool) -> SocialBackend {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uitest-social-demo") {
            return DemoSocialBackend()
        }
        #endif
        return SupabaseSocialBackend(inMemorySession: isUITest)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if appMounted {
                    RootView()
                } else {
                    Theme.launchBackground.ignoresSafeArea()
                }
            }
                .environment(location)
                .environment(recorder)
                .environment(announcer)
                .environment(social)
                .environment(health)
                .environment(watchSync)
                .environment(mirror)
                .environment(celebration)
                .environment(recovery)
                .environment(holiday)
                .environment(\.runAutosave, autosave)
                .preferredColorScheme(.dark)
                // The wordmark plays on an idle main thread; the app is laid
                // out (map included) under the hold, so the fade lands on a
                // ready screen.
                .overlay {
                    if splash {
                        LaunchSplashView(holiday: holiday.current,
                                         onReveal: { appMounted = true },
                                         onFinished: { splash = false })
                            .zIndex(2)
                    }
                }
                // The app can be killed at any point once it is off screen;
                // write the run now rather than up to `interval` from now.
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { autosave.tick() }
                    // A theme can start overnight while the app sits in the
                    // background; the icon can only change while active.
                    if phase == .active { holiday.refresh() }
                }
                .task {
                    // A rescued run is shared and written to Health exactly
                    // as a normal save would have done.
                    if let activity = recoveredActivity {
                        recoveredActivity = nil
                        Task { await social.share(activity) }
                        if UserDefaults.standard.bool(forKey: HealthSettings.enabledKey) {
                            await HealthSync.write(activity, using: health, context: container.mainContext,
                                                   includeRoute: UserDefaults.standard.bool(forKey: HealthSettings.routeKey))
                        }
                    }
                    watchSync.activate()
                    // The watch calls startMirroringToCompanionDevice when a
                    // workout begins; without this handler installed the phone
                    // never hears about it.
                    mirror.begin()
                    // The weight the calorie estimate scales with. Asking for
                    // it here rather than mid-save keeps the save instant, and
                    // it is a no-op until the user has allowed Health.
                    guard UserDefaults.standard.bool(forKey: HealthSettings.enabledKey) else { return }
                    await health.refreshBodyMass()
                }
        }
        .modelContainer(container)
    }
}

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
            RootView()
                .environment(location)
                .environment(recorder)
                .environment(announcer)
                .environment(social)
                .environment(health)
                .environment(watchSync)
                .environment(mirror)
                .environment(celebration)
                .preferredColorScheme(.dark)
                .task {
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

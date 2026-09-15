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
    @State private var celebration = SaveCelebration()

    let container: ModelContainer

    init() {
        let isUITest = ProcessInfo.processInfo.arguments.contains("-uitest")
        if isUITest, let bundle = Bundle.main.bundleIdentifier {
            // Settings must not leak from one UI run into the next (an aborted
            // test once left voice cues on and broke the following run).
            UserDefaults.standard.removePersistentDomain(forName: bundle)
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
                .environment(celebration)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}

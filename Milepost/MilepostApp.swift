import SwiftData
import SwiftUI

@main
struct MilepostApp: App {
    @State private var location: LocationService
    @State private var recorder: RunRecorder

    let container: ModelContainer

    init() {
        let location = LocationService()
        let recorder = RunRecorder()
        location.onUpdate = { recorder.ingest($0) }
        _location = State(initialValue: location)
        _recorder = State(initialValue: recorder)

        let isUITest = ProcessInfo.processInfo.arguments.contains("-uitest")
        let config = ModelConfiguration(isStoredInMemoryOnly: isUITest)
        do {
            container = try ModelContainer(for: Activity.self, configurations: config)
        } catch {
            // A corrupt store on disk should not brick the app; start clean.
            container = try! ModelContainer(for: Activity.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(location)
                .environment(recorder)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
    }
}

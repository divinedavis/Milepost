import SwiftUI

@main
struct MilepostWatchApp: App {
    @State private var workout: WatchWorkoutController
    @State private var sync = WatchPhoneSync()
    /// Not observed by any view; held so the milestone cues have a voice for
    /// the life of the process. Settings are mirrored from the phone by
    /// WatchPhoneSync into this watch's defaults, which is what it reads.
    @State private var announcer = VoiceAnnouncer()

    init() {
        #if DEBUG
        if WatchPreviewData.isRequested {
            let controller = WatchWorkoutController(recorder: WatchPreviewData.makeRecorder())
            _workout = State(initialValue: controller)
            return
        }
        #endif
        let controller = WatchWorkoutController()
        let announcer = VoiceAnnouncer()
        controller.recorder.onMilestone = { announcer.announce($0) }
        _workout = State(initialValue: controller)
        _announcer = State(initialValue: announcer)
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(workout)
                .environment(sync)
                .tint(Theme.orange)
                .onChange(of: sync.includeRouteInHealth) { _, include in
                    workout.includeRouteInHealth = include
                }
                .task {
                    #if DEBUG
                    if WatchPreviewData.isRequested {
                        // No Health sheet, no location prompt, no session.
                        if ProcessInfo.processInfo.arguments.contains("-watch-preview-summary") {
                            workout.enterPreviewSummary()
                        } else {
                            workout.enterPreviewState()
                            if ProcessInfo.processInfo.arguments.contains("-watch-preview-paused") {
                                workout.pause()
                            }
                        }
                        return
                    }
                    #endif
                    sync.activate()
                    // Ending from the phone still has to reach the phone's
                    // activity list, so it goes through the same queue.
                    workout.onRemoteEnd = { [sync] payload in sync.send(payload) }
                    workout.includeRouteInHealth = sync.includeRouteInHealth
                    // Health is asked for when a run starts, not here. Opening
                    // an app should not put permission sheets in your face
                    // before you have done anything.
                }
        }
    }
}

import SwiftUI

@main
struct MilepostWatchApp: App {
    @State private var workout: WatchWorkoutController
    @State private var sync = WatchPhoneSync()

    init() {
        #if DEBUG
        if WatchPreviewData.isRequested {
            let controller = WatchWorkoutController(recorder: WatchPreviewData.makeRecorder())
            _workout = State(initialValue: controller)
            return
        }
        #endif
        _workout = State(initialValue: WatchWorkoutController())
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

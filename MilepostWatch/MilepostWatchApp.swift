import SwiftUI

@main
struct MilepostWatchApp: App {
    @State private var workout = WatchWorkoutController()
    @State private var sync = WatchPhoneSync()

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
                    sync.activate()
                    // Ending from the phone still has to reach the phone's
                    // activity list, so it goes through the same queue.
                    workout.onRemoteEnd = { [sync] payload in sync.send(payload) }
                    workout.includeRouteInHealth = sync.includeRouteInHealth
                    // Asked once, on first launch, so the Start button never
                    // stalls behind two system sheets mid-run.
                    await workout.requestAuthorization()
                    if workout.location.isUndetermined {
                        workout.location.requestPermission()
                    }
                }
        }
    }
}

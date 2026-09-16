import SwiftUI

/// Start screen, live workout, and summary — chosen by the controller's phase
/// rather than by navigation, so a workout resumed from the background always
/// lands on the live screen and never behind a stale push.
struct WatchRootView: View {
    @Environment(WatchWorkoutController.self) private var workout

    var body: some View {
        switch workout.phase {
        case .idle:
            WatchStartView()
        case .running, .paused, .ending:
            WatchSessionView()
        case .finished:
            WatchSummaryView()
        }
    }
}

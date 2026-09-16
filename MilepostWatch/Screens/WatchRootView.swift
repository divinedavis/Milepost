import SwiftUI

/// Start screen, live workout, and summary — chosen by the controller's phase
/// rather than by navigation, so a workout resumed from the background always
/// lands on the live screen and never behind a stale push.
struct WatchRootView: View {
    @Environment(WatchWorkoutController.self) private var workout

    var body: some View {
        // One stable container with a cross-fade, rather than a bare switch.
        // A bare switch swaps whole view *types* — a NavigationStack with a
        // List for a paged TabView — which SwiftUI tears down and rebuilds with
        // no transition, and the first press of Start visibly snaps.
        ZStack {
            switch workout.phase {
            case .idle:
                WatchStartView()
                    .transition(.opacity)
            case .running, .paused, .ending:
                WatchSessionView()
                    .transition(.opacity)
            case .finished:
                WatchSummaryView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: workout.phase)
    }
}

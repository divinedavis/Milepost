import SwiftUI

/// The live workout, as three vertically paged screens: controls above,
/// metrics in the middle where a run opens, splits below.
///
/// Pause is on **both** the controls page and the metrics page, on purpose.
/// Pausing is the thing you do most during a run and metrics is the page you
/// are already looking at; a control that needs a swipe you have to know about
/// is not a control you can use with cold hands at a red light.
struct WatchSessionView: View {
    @Environment(WatchWorkoutController.self) private var workout
    @State private var page = Page.initial

    private enum Page: Hashable {
        case controls, metrics, splits

        /// Metrics is the default: it is what you want on the way up. The
        /// override exists only so the other two can be captured, since
        /// watchOS has no way to drive a swipe from a test.
        static var initial: Page {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-watch-preview-page-splits") { return .splits }
            if arguments.contains("-watch-preview-page-controls") { return .controls }
            #endif
            return .metrics
        }
    }

    var body: some View {
        TabView(selection: $page) {
            WatchControlsPage().tag(Page.controls)
            WatchMetricsPage().tag(Page.metrics)
            WatchSplitsPage().tag(Page.splits)
        }
        .tabViewStyle(.verticalPage)
        // The workout session keeps the app running with the wrist down; this
        // is what keeps the screen showing the run rather than the watch face
        // when it comes back up.
        .navigationTitle(workout.recorder.sport.title)
    }
}

private struct WatchControlsPage: View {
    @Environment(WatchWorkoutController.self) private var workout
    @Environment(WatchPhoneSync.self) private var sync
    @State private var confirmEnd = false

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 18) {
                Button {
                    confirmEnd = true
                } label: {
                    Label("End", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                }
                .tint(.red)
                .accessibilityIdentifier("watch.end")

                Button {
                    workout.toggle()
                } label: {
                    Label(workout.phase == .paused ? "Resume" : "Pause",
                          systemImage: workout.phase == .paused ? "play.fill" : "pause.fill")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                }
                .tint(workout.phase == .paused ? Theme.accent : Theme.paused)
                .accessibilityIdentifier("watch.toggle")
            }

            Text(workout.phase == .paused ? (workout.recorder.isAutoPaused ? "Auto-paused" : "Paused") : "Recording")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog("End this \(workout.recorder.sport.title.lowercased())?",
                            isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End", role: .destructive) {
                Task {
                    if let payload = await workout.end() {
                        sync.send(payload)
                    }
                }
            }
            Button("Keep going", role: .cancel) {}
        }
    }
}

private struct WatchMetricsPage: View {
    @Environment(WatchWorkoutController.self) private var workout
    @AppStorage(DistanceUnit.storageKey) private var unitRaw = DistanceUnit.miles.rawValue

    private var unit: DistanceUnit { workout.recorder.isActive ? workout.recorder.unit : (DistanceUnit(rawValue: unitRaw) ?? .miles) }
    private var sport: Sport { workout.recorder.sport }
    private var isPaused: Bool { workout.phase == .paused }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Counted by the system from the anchor, so it ticks without the
            // app publishing a change every second — the same trick the Live
            // Activity on the phone uses.
            if let anchor = workout.recorder.elapsedAnchor, workout.phase == .running {
                Text(anchor, style: .timer)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
            } else {
                Text(Format.clock(workout.recorder.elapsed))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.paused)
            }

            metric(Format.distance(workout.recorder.distanceMeters, unit: unit), unit.abbreviation)
            metric(sport.rateText(workout.recorder.currentSplitPace ?? workout.recorder.averagePace, unit: unit),
                   sport.rateSuffix(unit: unit))
            metric(Format.elevation(workout.recorder.elevationGainMeters, unit: unit),
                   "\(unit.elevationAbbreviation) up")
            if let bpm = workout.heartRate {
                metric("\(Int(bpm.rounded()))", "bpm")
            }
            if let kcal = workout.activeKilocalories {
                metric("\(Int(kcal.rounded()))", "kcal")
            }

            Spacer(minLength: 6)

            // End deliberately stays on the controls page. Ending by accident
            // loses a run; pausing by accident costs a tap.
            Button {
                workout.toggle()
            } label: {
                Label(isPaused ? "Resume" : "Pause",
                      systemImage: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .tint(isPaused ? Theme.accent : Theme.paused)
            .accessibilityIdentifier("watch.metrics.toggle")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("watch.metrics")
    }

    private func metric(_ value: String, _ suffix: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(suffix)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WatchSplitsPage: View {
    @Environment(WatchWorkoutController.self) private var workout

    var body: some View {
        let unit = workout.recorder.unit
        let sport = workout.recorder.sport
        let splits = workout.recorder.splits.reversed()
        let fastestIndex = workout.recorder.splits.fastestIndex(splitMeters: workout.recorder.splitMeters, unit: unit, sport: sport)
        List {
            if splits.isEmpty {
                Text("Splits appear after your first \(unit.splitNoun.lowercased()).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(splits)) { split in
                HStack {
                    Text(split.isComplete(splitMeters: workout.recorder.splitMeters)
                         ? "\(split.index)"
                         : String(format: "%.2f", split.distanceMeters / unit.meters))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                    if split.index == fastestIndex {
                        Image(systemName: "bolt.fill").font(.caption2).foregroundStyle(Theme.accent)
                            .accessibilityLabel("Fastest")
                    }
                    Spacer()
                    Text(sport.rateText(split.pace(unit: unit, sport: sport), unit: unit))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(split.isComplete(splitMeters: workout.recorder.splitMeters) ? Theme.accent : .secondary)
                }
            }
        }
        .navigationTitle("Splits")
    }
}

import SwiftUI

/// The live workout, as three swipeable pages in the order the wrist wants
/// them: controls to the left where a thumb lands, metrics in the middle as the
/// default, splits to the right.
struct WatchSessionView: View {
    @Environment(WatchWorkoutController.self) private var workout
    @State private var page = Page.metrics

    private enum Page: Hashable { case controls, metrics, splits }

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
                .tint(workout.phase == .paused ? Theme.orange : Theme.paused)
                .accessibilityIdentifier("watch.toggle")
            }

            Text(workout.phase == .paused ? "Paused" : "Recording")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Counted by the system from the anchor, so it ticks without the
            // app publishing a change every second — the same trick the Live
            // Activity on the phone uses.
            if let anchor = workout.recorder.elapsedAnchor, workout.phase == .running {
                Text(anchor, style: .timer)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.orange)
            } else {
                Text(Format.clock(workout.recorder.elapsed))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.paused)
            }

            metric(Format.distance(workout.recorder.distanceMeters, unit: unit), unit.abbreviation)
            metric(sport.rateText(workout.recorder.currentSplitPace ?? workout.recorder.averagePace, unit: unit),
                   sport.rateSuffix(unit: unit))
            if let bpm = workout.heartRate {
                metric("\(Int(bpm.rounded()))", "bpm")
            }
            if let kcal = workout.activeKilocalories {
                metric("\(Int(kcal.rounded()))", "kcal")
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("watch.metrics")
    }

    private func metric(_ value: String, _ suffix: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
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
                    Spacer()
                    Text(sport.rateText(split.pace(unit: unit, sport: sport), unit: unit))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(split.isComplete(splitMeters: workout.recorder.splitMeters) ? Theme.orange : .secondary)
                }
            }
        }
        .navigationTitle("Splits")
    }
}

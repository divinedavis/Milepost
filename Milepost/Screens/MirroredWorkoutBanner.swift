import SwiftUI

/// Shown on the Record tab while a workout is running on the Apple Watch.
///
/// The watch is the recorder; this is a remote for it. Starting a second
/// recording on the phone at the same time is blocked rather than merged — one
/// run should not become two activities and two workouts in Health.
struct MirroredWorkoutBanner: View {
    @Environment(MirroredWorkoutMonitor.self) private var mirror
    @State private var confirmEnd = false

    var body: some View {
        if mirror.isMirroring {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "applewatch")
                        .foregroundStyle(Theme.accent)
                    Text("Recording on Apple Watch")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }

                if let state = mirror.state {
                    HStack(alignment: .firstTextBaseline, spacing: 18) {
                        timeStat(for: state)
                        stat("\(Format.distance(state.distanceMeters, unit: state.unit)) \(state.unit.abbreviation)", "distance")
                        stat("\(state.sport.rateText(state.paceSecondsPerUnit, unit: state.unit))",
                             state.sport.rateNoun)
                        if let bpm = state.heartRate {
                            stat("\(Int(bpm.rounded()))", "bpm")
                        }
                    }
                } else {
                    Text("Waiting for your watch…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button(isPaused ? "Resume" : "Pause") {
                        isPaused ? mirror.resume() : mirror.pause()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("mirror.toggle")

                    Button("End", role: .destructive) { confirmEnd = true }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("mirror.end")
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("mirror.banner")
            .confirmationDialog("End the workout on your Apple Watch?",
                                isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End", role: .destructive) { mirror.end() }
                Button("Keep going", role: .cancel) {}
            }
        }
    }

    private var isPaused: Bool { mirror.state?.isPaused ?? false }

    /// The watch pushes a snapshot every couple of seconds. Counting from the
    /// anchor it sends lets the phone tick every second in between, so the
    /// clock reads like a stopwatch instead of stepping two at a time. A paused
    /// run has no anchor and shows a frozen number, which is the truth.
    @ViewBuilder
    private func timeStat(for state: MirroredWorkoutState) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let anchor = state.elapsedAnchor, !state.isPaused {
                Text(anchor, style: .timer)
                    .font(.title3.weight(.semibold)).monospacedDigit()
            } else {
                Text(Format.clock(state.elapsed))
                    .font(.title3.weight(.semibold)).monospacedDigit()
            }
            Text("time").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

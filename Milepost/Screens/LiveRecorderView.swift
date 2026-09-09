import SwiftUI

/// The full-screen recorder: clock, split pace, distance, splits, controls.
/// Yellow header while paused, like the reference.
struct LiveRecorderView: View {
    @Environment(RunRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss

    private var isPaused: Bool { recorder.state == .paused }

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 24)
            bigStat(recorder.sport.rateText(recorder.currentSplitPace, unit: recorder.unit),
                    recorder.sport.rateLabel(isPaused ? "Avg." : "Split avg.", unit: recorder.unit),
                    size: 84, id: "live.pace")
            Spacer(minLength: 24)
            bigStat(Format.distance(recorder.distanceMeters, unit: recorder.unit),
                    "Distance (\(recorder.unit.abbreviation))",
                    size: 110, id: "live.distance")
            Spacer(minLength: 24)
            SplitsBar(splits: recorder.splits, unit: recorder.unit, sport: recorder.sport)
                .padding(.horizontal, 24)
            Text("Splits (\(recorder.unit.abbreviation))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 8)
            Spacer(minLength: 16)
            controls
        }
        .background(Theme.background.ignoresSafeArea())
        .onChange(of: recorder.state) { _, state in
            if state == .idle { dismiss() }
        }
        .onAppear {
            // Opened with nothing running (should not happen); do not strand
            // the user on a dead screen.
            if !recorder.isActive { dismiss() }
        }
    }

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                if isPaused {
                    Text("Paused")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .accessibilityIdentifier("live.pausedBanner")
                }
                Text(Format.clock(recorder.elapsed, forceHours: true))
                    .font(.stat(72))
                    .monospacedDigit()
                    .foregroundStyle(isPaused ? .black : .white)
                    .accessibilityIdentifier("live.time")
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 14)

            Button { dismiss() } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isPaused ? .black : .white)
                    .padding(14)
            }
            .accessibilityLabel("Collapse recorder")
            .accessibilityIdentifier("live.collapse")
        }
        .background(isPaused ? Theme.paused : Theme.background)
        .background(alignment: .top) {
            // Paint the banner colour up under the status bar too.
            (isPaused ? Theme.paused : Theme.background).ignoresSafeArea(edges: .top)
        }
    }

    private func bigStat(_ value: String, _ label: String, size: CGFloat, id: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.stat(size))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(.white)
                .accessibilityIdentifier(id)
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 16)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Color(white: 0.3))
                .frame(width: 56, height: 5)
            RecorderControls(layout: .live)
                .padding(.horizontal, 20)
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Theme.card)
    }
}

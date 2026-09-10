import ActivityKit
import SwiftUI
import WidgetKit

/// The run in the Dynamic Island and on the lock screen. Laid out like a
/// ride-share pickup card: wordmark, how far so far as the headline, the
/// mile in progress and the pace
/// under it, the clock on the right, and a track along the bottom with the
/// runner moving toward the next milepost.
struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            LockScreenCard(context: context)
                .activityBackgroundTint(Theme.background)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Image("Wordmark")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 16)
                            .accessibilityLabel("Milepost")
                            .padding(.bottom, 4)
                        Headline(context: context)
                    }
                    .padding(.leading, 4)
                    .padding(.top, 2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RunClock(state: context.state, size: 26)
                        .padding(.trailing, 4)
                        .padding(.top, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TrackRow(context: context)
                        .padding(.horizontal, 4)
                        .padding(.top, 6)
                        .padding(.bottom, 2)
                }
            } compactLeading: {
                RunnerMark(sport: context.attributes.sport, isPaused: context.state.isPaused)
            } compactTrailing: {
                // How far, not which mile: the mile number would sit here
                // unchanged for a whole mile and read as frozen.
                Text(context.state.distanceText(unit: context.attributes.unit))
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            } minimal: {
                RunnerMark(sport: context.attributes.sport, isPaused: context.state.isPaused)
            }
            .keylineTint(Theme.orange)
        }
    }
}

// MARK: - Pieces

private struct RunnerMark: View {
    let sport: Sport
    let isPaused: Bool
    var body: some View {
        Image(systemName: isPaused ? "pause.fill" : sport.symbol)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(isPaused ? Theme.paused : Theme.orange)
            // The compact island has no room for the word, so this icon is
            // the only thing that says a run is paused. Spell it out for
            // VoiceOver (and it is what the UI test asserts on).
            .accessibilityLabel(isPaused ? "Paused" : sport.title)
    }
}

/// How far, with the mile in progress and the pace under it.
private struct Headline: View {
    let context: ActivityViewContext<RunActivityAttributes>
    var body: some View {
        let unit = context.attributes.unit
        VStack(alignment: .leading, spacing: 2) {
            Text(context.state.distanceText(unit: unit))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(context.state.detailText(unit: unit, sport: context.attributes.sport))
                .font(.system(size: 14))
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// Elapsed moving time. Counts on its own while recording; frozen while paused.
private struct RunClock: View {
    let state: RunActivityAttributes.ContentState
    var size: CGFloat
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Group {
                switch state.clock {
                case .running(let since):
                    Text(timerInterval: since...since.addingTimeInterval(24 * 3600),
                         countsDown: false, showsHours: false)
                case .paused(let elapsed):
                    Text(Format.clock(elapsed))
                }
            }
            .font(.system(size: size, weight: .bold))
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .foregroundStyle(state.isPaused ? Theme.paused : .white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(state.isPaused ? "Paused" : "Time")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(state.isPaused ? Theme.paused : Theme.secondaryText)
        }
    }
}

/// The bottom row: the Pause / Resume button, then the track.
private struct TrackRow: View {
    let context: ActivityViewContext<RunActivityAttributes>
    var body: some View {
        HStack(spacing: 12) {
            RecordingButton(isPaused: context.state.isPaused)
            MileTrack(fraction: context.state.splitFraction,
                      sport: context.attributes.sport,
                      isPaused: context.state.isPaused,
                      label: context.state.trackDescription(unit: context.attributes.unit))
        }
    }
}

/// Pauses or resumes the run without opening the app. The system runs the
/// intent in the app's process, so it reaches the live recorder.
private struct RecordingButton: View {
    let isPaused: Bool

    var body: some View {
        Button(intent: ToggleRecordingIntent()) {
            Label(isPaused ? "Resume" : "Pause",
                  systemImage: isPaused ? "play.fill" : "pause.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isPaused ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isPaused ? Theme.paused : Color(white: 0.24), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(isPaused ? "island.resume" : "island.pause")
        .layoutPriority(1)
    }
}

/// A line from this milepost to the next, with the athlete where they are on
/// it. The marker sits in a black halo so it reads as riding on the track.
private struct MileTrack: View {
    let fraction: Double
    let sport: Sport
    let isPaused: Bool
    var label: String = ""

    private let markerSize: CGFloat = 26
    private let postSize: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let midY = geo.size.height / 2
            let startX = markerSize / 2
            let endX = width - postSize / 2
            let x = startX + (endX - startX) * CGFloat(min(1, max(0, fraction)))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: max(0, endX - startX), height: 4)
                    .offset(x: startX)
                Capsule()
                    .fill(isPaused ? Theme.paused : .white)
                    .frame(width: max(0, x - startX), height: 4)
                    .offset(x: startX)
                Circle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: postSize, height: postSize)
                    .overlay(Circle().fill(.black).frame(width: 6, height: 6))
                    .position(x: endX, y: midY)
                Image(systemName: sport.symbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isPaused ? Theme.paused : Theme.orange)
                    .frame(width: markerSize, height: markerSize)
                    .background(Circle().fill(.black))
                    .position(x: x, y: midY)
            }
        }
        .frame(height: markerSize)
        .accessibilityLabel(label)
    }
}

/// Lock screen and banner: the same card, with room to breathe.
private struct LockScreenCard: View {
    let context: ActivityViewContext<RunActivityAttributes>
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Image("Wordmark")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 18)
                        .accessibilityLabel("Milepost")
                    Headline(context: context)
                }
                Spacer(minLength: 12)
                RunClock(state: context.state, size: 30)
            }
            TrackRow(context: context)
        }
        .padding(16)
        .opacity(context.isStale ? 0.6 : 1)
    }
}

import ActivityKit
import SwiftUI
import WidgetKit

/// The run in the Dynamic Island and on the lock screen, laid out like the
/// system Now Playing card so it reads the same way: a sport tile where the
/// artwork goes, how far so far as the title, the mile and pace under it; a
/// progress line through the mile where the scrubber goes, the clock on its
/// left and the distance to the next milepost on its right (as Music shows
/// time left); and Pause / Resume alone in the middle of the bottom row,
/// where the play/pause button sits.
///
/// Height budget: a third-party Live Activity is capped at 160 pt (Music, a
/// system app, is not — it runs ~207 pt). Anything past the cap is clipped
/// silently; the first version of this layout lost its Pause button that
/// way. The sizes below fit all three rows inside 160 pt: tile 52, progress
/// row ~20, controls row 40, with tight spacing.
struct RunLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            LockScreenCard(context: context)
                .activityBackgroundTint(Theme.background)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SportTile(sport: context.attributes.sport, isPaused: context.state.isPaused, size: 52)
                        .padding(.leading, 6)
                        .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveIndicator(isPaused: context.state.isPaused)
                        .padding(.trailing, 8)
                        .padding(.top, 8)
                }
                DynamicIslandExpandedRegion(.center) {
                    TitleBlock(context: context)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressRow(context: context)
                        ControlsRow(isPaused: context.state.isPaused)
                    }
                    .padding(.horizontal, 6)
                    .padding(.top, 8)
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

/// Where Now Playing shows the album art.
private struct SportTile: View {
    let sport: Sport
    let isPaused: Bool
    let size: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
            .fill(isPaused ? Theme.paused : Theme.orange)
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: sport.symbol)
                    .font(.system(size: size * 0.46, weight: .bold))
                    .foregroundStyle(isPaused ? .black : .white)
            )
            .accessibilityLabel(sport.title)
    }
}

/// Where Now Playing shows its sound bars: recording, or paused.
private struct LiveIndicator: View {
    let isPaused: Bool
    var body: some View {
        Image(systemName: isPaused ? "pause.circle.fill" : "dot.radiowaves.left.and.right")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(isPaused ? Theme.paused : Theme.orange)
            .accessibilityLabel(isPaused ? "Paused" : "Recording")
    }
}

/// How far, with the mile in progress and the pace under it: the song title
/// and artist line.
private struct TitleBlock: View {
    let context: ActivityViewContext<RunActivityAttributes>
    var body: some View {
        let unit = context.attributes.unit
        VStack(alignment: .leading, spacing: 1) {
            Text(context.state.distanceText(unit: unit))
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(context.state.detailText(unit: unit, sport: context.attributes.sport))
                .font(.system(size: 15))
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// The scrubber row: elapsed time, the line through the mile, distance left.
/// Both labels use the same size and weight, as the player's do.
private struct ProgressRow: View {
    let context: ActivityViewContext<RunActivityAttributes>
    var body: some View {
        let state = context.state
        let unit = context.attributes.unit
        HStack(spacing: 8) {
            ElapsedClock(state: state)
            MileBar(fraction: state.splitFraction, isPaused: state.isPaused,
                    label: state.trackDescription(unit: unit))
            Text(state.remainingText(unit: unit))
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel(state.remainingDescription(unit: unit))
        }
        .frame(height: 20)
    }
}

/// Elapsed moving time. Counts on its own while recording; frozen while paused.
private struct ElapsedClock: View {
    let state: RunActivityAttributes.ContentState
    var body: some View {
        Group {
            switch state.clock {
            case .running(let since):
                Text(timerInterval: since...since.addingTimeInterval(24 * 3600),
                     countsDown: false, showsHours: false)
            case .paused(let elapsed):
                Text(Format.clock(elapsed))
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .monospacedDigit()
        .foregroundStyle(state.isPaused ? Theme.paused : Theme.secondaryText)
        .lineLimit(1)
        // A timer Text claims every point it is offered; pin it to what
        // "59:59" needs, like the player's time label, so the line starts
        // right after it. No scale factor: it shrank the clock below the
        // distance label on the other end.
        .frame(width: 42, alignment: .leading)
    }
}

/// The line from this milepost to the next, filled as far as the athlete has
/// got, in the place and proportions of the Now Playing scrubber.
private struct MileBar: View {
    let fraction: Double
    let isPaused: Bool
    let label: String
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                Capsule()
                    .fill(isPaused ? Theme.paused : Color.white.opacity(0.9))
                    .frame(width: geo.size.width * CGFloat(min(1, max(0, fraction))))
            }
        }
        .frame(height: 7)
        .accessibilityElement()
        .accessibilityLabel(label)
    }
}

/// Pause / Resume, alone in the middle of the bottom row where the player
/// puts play/pause. The system runs the intent in the app's process, so it
/// reaches the live recorder.
private struct ControlsRow: View {
    let isPaused: Bool
    var body: some View {
        HStack {
            Spacer(minLength: 0)
            Button(intent: ToggleRecordingIntent()) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPaused ? "Resume" : "Pause")
            .accessibilityIdentifier(isPaused ? "island.resume" : "island.pause")
            Spacer(minLength: 0)
        }
    }
}

/// Lock screen and banner: the same three rows as the expanded island, under
/// the same 160 pt cap.
private struct LockScreenCard: View {
    let context: ActivityViewContext<RunActivityAttributes>
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                SportTile(sport: context.attributes.sport, isPaused: context.state.isPaused, size: 48)
                TitleBlock(context: context)
                Spacer(minLength: 8)
                LiveIndicator(isPaused: context.state.isPaused)
            }
            ProgressRow(context: context)
            ControlsRow(isPaused: context.state.isPaused)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(context.isStale ? 0.6 : 1)
    }
}

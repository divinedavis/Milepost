import SwiftUI
import WatchKit

/// Pick a sport and go. Everything else the phone asks about — title, voice
/// cues, sharing — is decided after the fact or not at all on the wrist.
///
/// Four square tiles in a 2×2 grid rather than a list, because all four sports
/// have to be on screen at once. As a list, Ride sat below the fold on every
/// watch size: a sport you have to scroll to find is one you will not use, and
/// scrolling for it is the wrong thing to be doing at the start of a ride.
/// There is no title for the same reason — the grid needs the height, and the
/// icons say what the app is.
struct WatchStartView: View {
    @Environment(WatchWorkoutController.self) private var workout
    @Environment(WatchPhoneSync.self) private var sync
    @AppStorage(DistanceUnit.storageKey) private var unitRaw = DistanceUnit.miles.rawValue
    @AppStorage(Sport.storageKey) private var sportRaw = Sport.run.rawValue

    /// A sport waiting on the location prompt, so the run starts the moment
    /// the answer comes back rather than needing a second press.
    @State private var pendingSport: Sport?

    private var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .miles }
    private var sport: Sport { Sport(rawValue: sportRaw) ?? .run }

    private static let spacing: CGFloat = 6
    private static let sideInset: CGFloat = 4

    /// The tile side that puts all four on screen at once.
    ///
    /// Width alone is not enough: at full column width two rows are a few
    /// points taller than the visible area and the bottom row is clipped. The
    /// height has to bound it too, which means measuring the space actually
    /// available rather than the whole screen — `aspectRatio(1, .fit)` inside a
    /// `ScrollView` cannot, because a scroll view offers unbounded height, and
    /// it silently falls back to the content's natural size.
    private func tileSide(in size: CGSize) -> CGFloat {
        let byWidth = (size.width - Self.spacing) / 2
        let byHeight = (size.height - Self.spacing) / 2
        return max(52, min(byWidth, byHeight))
    }

    private var rows: [[Sport]] {
        stride(from: 0, to: Sport.allCases.count, by: 2).map {
            Array(Sport.allCases[$0..<min($0 + 2, Sport.allCases.count)])
        }
    }

    var body: some View {
        // The GeometryReader is outside the ScrollView on purpose: inside one
        // it would report unbounded height and the sizing would be meaningless.
        GeometryReader { geo in
            let side = tileSide(in: geo.size)
            ScrollView {
                VStack(spacing: Self.spacing) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: Self.spacing) {
                            ForEach(row) { option in
                                tile(option, side: side)
                            }
                        }
                    }
                }
                .frame(height: geo.size.height)

                // Below the fold by design. The grid always fills exactly one
                // screen; these are occasional and worth scrolling for.
                VStack(spacing: 6) {
                    if let error = workout.errorText {
                        status(error)
                    }
                    if workout.location.isDenied {
                        status("Location is off for Milepost, so distance and pace cannot be measured. Turn it on in the Watch app on your iPhone.")
                    }
                    if sync.pendingCount > 0 {
                        status("\(sync.pendingCount) activity\(sync.pendingCount == 1 ? "" : "s") waiting to reach your iPhone.")
                            .accessibilityIdentifier("watch.pending")
                    }
                }
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, Self.sideInset, for: .scrollContent)
        }
        .onChange(of: workout.location.authorization) { _, _ in
            guard let pending = pendingSport else { return }
            pendingSport = nil
            // Denied is not a reason to start: a run with no fixes measures
            // nothing, and the grid already explains what to do about it.
            guard workout.location.isAuthorized else { return }
            workout.start(sport: pending, unit: unit)
        }
    }

    private func tile(_ option: Sport, side: CGFloat) -> some View {
        let tint: Color = option == sport ? Theme.orange : .primary
        return Button {
            sportRaw = option.rawValue
            start(option)
        } label: {
            // Label if it fits on one line, mark alone if it does not.
            //
            // "Stroller Run" is the one that decides this, and on a 41 or 42mm
            // watch the tile is too narrow for it. Wrapping it to "Stroller /
            // Run" or truncating to "Strol…" both look broken and neither reads
            // any faster than the runner-with-a-pushchair mark, which is
            // unmistakable on its own. ViewThatFits picks the first candidate
            // whose intrinsic width fits the proposed one, which is exactly
            // this rule — the `.frame` below is what proposes the tile width.
            ViewThatFits(in: .horizontal) {
                labelled(option, tint: tint, size: 13)
                labelled(option, tint: tint, size: 11)
                SportIcon(sport: option, size: 34, weight: .semibold)
                    .foregroundStyle(tint)
            }
            .frame(width: side, height: side)
        }
        .buttonStyle(.plain)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(option == sport ? Theme.orange : .clear, lineWidth: 2)
        )
        // The mark-only tile has no text, so the name has to be said here or
        // VoiceOver announces nothing but "button".
        .accessibilityLabel(option.title)
        .accessibilityIdentifier("watch.start.\(option.rawValue)")
    }

    /// A tile with its name under the mark, at a fixed size so `ViewThatFits`
    /// can tell whether it actually fits. Two sizes are offered before giving
    /// up on the label: a 46mm watch has room for "Stroller Run" at 11pt and
    /// there is no reason to throw the word away there.
    private func labelled(_ option: Sport, tint: Color, size: CGFloat) -> some View {
        VStack(spacing: 4) {
            SportIcon(sport: option, size: 24, weight: .semibold)
                .foregroundStyle(tint)
            Text(option.title)
                .font(.system(size: size, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 4)
        }
    }

    private func status(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    /// Location is asked for **here**, on the press that needs it, and never at
    /// launch. Opening an app should not put a permission sheet in your face
    /// before you have done anything.
    ///
    /// When the prompt is needed the run waits for the answer instead of
    /// starting underneath it — which is what made the first press of Start
    /// look broken: the alert appeared on top of a screen that was already
    /// swapping to the live view. Otherwise `start` returns immediately and the
    /// screen changes on the same run loop pass.
    private func start(_ sport: Sport) {
        guard !workout.location.isUndetermined else {
            pendingSport = sport
            workout.location.requestPermission()
            return
        }
        guard workout.location.isAuthorized else { return }
        workout.start(sport: sport, unit: unit)
    }
}

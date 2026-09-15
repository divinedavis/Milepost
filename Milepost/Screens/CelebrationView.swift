import SwiftUI

/// What was just saved, handed from the save sheet to RootView. The sheet and
/// the full-screen recorder are both gone a moment after Save, so the splash
/// has to live above them.
@MainActor
@Observable
final class SaveCelebration {
    struct Moment: Identifiable {
        let id = UUID()
        let title: String
        let summary: RunSummary
    }

    var moment: Moment?

    func celebrate(title: String, summary: RunSummary) {
        moment = Moment(title: title, summary: summary)
    }
}

/// The congratulations splash shown over everything once an activity is saved.
struct CelebrationView: View {
    @AppStorage(DistanceUnit.storageKey) private var unitRaw = DistanceUnit.miles.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let moment: SaveCelebration.Moment
    let onDone: () -> Void

    @State private var appeared = false

    private var unit: DistanceUnit { DistanceUnit(rawValue: unitRaw) ?? .miles }
    private var summary: RunSummary { moment.summary }
    private var sport: Sport { summary.sport }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if !reduceMotion { Confetti(isFalling: appeared) }

            VStack(spacing: 28) {
                Spacer()
                badge
                VStack(spacing: 8) {
                    Text(headline)
                        .font(.system(size: 34, weight: .heavy))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("celebrate.title")
                    Text("\(moment.title) is saved.")
                        .font(.body)
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 16)

                stats
                    .padding(.horizontal, 20)
                    .opacity(appeared ? 1 : 0)
                Spacer()
                Button(action: onDone) {
                    Text("Done")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Theme.orange, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .accessibilityIdentifier("celebrate.done")
            }
        }
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear {
            withAnimation(reduceMotion ? .none : .spring(response: 0.55, dampingFraction: 0.65)) {
                appeared = true
            }
        }
    }

    private var headline: String {
        switch sport {
        case .run: return "Great run!"
        case .strollerRun: return "Great stroller run!"
        case .walk: return "Nice walk!"
        case .bike: return "Great ride!"
        }
    }

    private var badge: some View {
        ZStack {
            Circle()
                .fill(Theme.orange.opacity(0.18))
                .frame(width: 168, height: 168)
                .scaleEffect(appeared ? 1 : 0.6)
            Circle()
                .fill(Theme.orange)
                .frame(width: 120, height: 120)
                .overlay(SportIcon(sport: sport, size: 52).foregroundStyle(.white))
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(.white)
                        .frame(width: 38, height: 38)
                        .overlay(Image(systemName: "checkmark").font(.system(size: 18, weight: .bold)).foregroundStyle(Theme.orange))
                }
                .scaleEffect(appeared ? 1 : 0.3)
        }
        .accessibilityHidden(true)
    }

    private var stats: some View {
        let rate = Pace.secondsPerUnit(distanceMeters: summary.distanceMeters, seconds: summary.movingSeconds, unit: unit, sport: sport)
        return HStack(alignment: .firstTextBaseline) {
            stat(Format.distance(summary.distanceMeters, unit: unit), "Distance (\(unit.abbreviation))", id: "celebrate.distance")
            Spacer()
            stat(Format.duration(summary.movingSeconds), "Moving time", id: "celebrate.time")
            Spacer()
            stat(sport.rateText(rate, unit: unit), sport.rateLabel("Avg.", unit: unit), id: "celebrate.rate")
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
    }

    private func stat(_ value: String, _ label: String, id: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.stat(26))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(.white)
                .accessibilityIdentifier(id)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// A one-shot burst of confetti falling from the top of the screen.
private struct Confetti: View {
    let isFalling: Bool

    private struct Piece {
        let x: CGFloat
        let delay: Double
        let duration: Double
        let size: CGFloat
        let spin: Double
        let color: Color
    }

    private static let colors: [Color] = [Theme.orange, Theme.paused, Theme.splitBlue, .white]

    @State private var pieces: [Piece] = (0..<48).map { i in
        Piece(x: .random(in: 0...1),
              delay: .random(in: 0...0.5),
              duration: .random(in: 1.8...3.2),
              size: .random(in: 6...11),
              spin: .random(in: 180...720) * (Bool.random() ? 1 : -1),
              color: colors[i % colors.count])
    }

    var body: some View {
        GeometryReader { geo in
            ForEach(pieces.indices, id: \.self) { i in
                let p = pieces[i]
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(p.color)
                    .frame(width: p.size, height: p.size * 0.5)
                    .rotationEffect(.degrees(isFalling ? p.spin : 0))
                    .position(x: p.x * geo.size.width,
                              y: isFalling ? geo.size.height + 20 : -20)
                    .opacity(isFalling ? 0 : 1)
                    .animation(.easeIn(duration: p.duration).delay(p.delay), value: isFalling)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

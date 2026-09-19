import SwiftUI

/// One bar per split, taller = faster. The split in progress is blue with an
/// accent underline; empty slots pad the row out so a fresh run still shows
/// three bars.
struct SplitsBar: View {
    let splits: [Split]
    let unit: DistanceUnit
    var sport: Sport = .run
    var minimumSlots = 3
    var maximumBars = 6

    private var visible: [Split] { Array(splits.suffix(maximumBars)) }
    private var placeholders: Int { max(0, minimumSlots - visible.count) }

    var body: some View {
        let paces = visible.compactMap { $0.pace(unit: unit, sport: sport) }
        let fastest = paces.min() ?? 0
        let slowest = paces.max() ?? 0

        HStack(alignment: .bottom, spacing: 12) {
            ForEach(visible) { split in
                let isCurrent = split.index == splits.last?.index
                VStack(spacing: 6) {
                    Text(sport.rateText(split.pace(unit: unit, sport: sport), unit: unit))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaryText)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isCurrent ? Theme.splitBlue : Theme.barIdle)
                        .frame(height: height(for: split.pace(unit: unit, sport: sport), fastest: fastest, slowest: slowest, isCurrent: isCurrent))
                    Rectangle()
                        .fill(isCurrent ? Theme.accent : .clear)
                        .frame(height: 4)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("splits.bar.\(split.index)")
            }
            ForEach(0..<placeholders, id: \.self) { _ in
                VStack(spacing: 6) {
                    Text(" ").font(.caption)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Theme.barIdle)
                        .frame(height: 36)
                    Rectangle().fill(.clear).frame(height: 4)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 150, alignment: .bottom)
    }

    private func height(for pace: Double?, fastest: Double, slowest: Double, isCurrent: Bool) -> CGFloat {
        let minH: CGFloat = 36
        let maxH: CGFloat = 110
        guard let pace else { return isCurrent ? maxH : minH }
        guard slowest > fastest else { return maxH }
        let t = (slowest - pace) / (slowest - fastest)   // 1 = fastest
        return minH + (maxH - minH) * CGFloat(t)
    }
}

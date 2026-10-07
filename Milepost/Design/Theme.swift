import SwiftUI

enum Theme {
    /// Navy blue (#3D6BE0). Brightened from a true navy, which is ~1.4:1 on
    /// the near-black background and disappears; this one is ~4:1.
    static let accent = Color(red: 0.24, green: 0.42, blue: 0.88)
    /// The accent as TEXT (#6B94FF): small labels in `accent` (the Start
    /// caption, the selected tab) came out ~4:1 on the near-black card, just
    /// under WCAG AA's 4.5:1 in the accessibility audit (2026-10-07). Fills
    /// and icons keep `accent`.
    static let accentText = Color(red: 0.42, green: 0.58, blue: 1.0)
    static let paused = Color(red: 1.0, green: 0.76, blue: 0.0)
    /// The split in progress. Lighter than `accent` so a partial split still
    /// reads apart from the completed ones beside it.
    static let splitBlue = Color(red: 0.62, green: 0.74, blue: 1.0)
    static let background = Color(red: 0.055, green: 0.055, blue: 0.055)
    /// `LaunchBackground` in the asset catalog (#0E0E0E), which the static
    /// launch screen paints; the animated splash paints the same one so the
    /// hand-off between them is invisible.
    static let launchBackground = Color(red: 0x0E / 255.0, green: 0x0E / 255.0, blue: 0x0E / 255.0)
    static let card = Color(red: 0.11, green: 0.11, blue: 0.11)
    static let barIdle = Color(red: 0.22, green: 0.22, blue: 0.22)
    static let secondaryText = Color(white: 0.7)
}

extension Font {
    static func stat(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }
}

extension Date {
    var activityDateText: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: self)
    }
}

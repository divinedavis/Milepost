import SwiftUI

/// Dark glass for everything that floats over the map: the Record panel, the
/// tab bar, the chips and the stats card.
///
/// iOS 26 and later: Apple's Liquid Glass with a dark tint (owner,
/// 2026-10-23, "use apples ios 26 liquid glass dark tint"), so it refracts and
/// catches light like the system's own bars. Earlier iOS keeps the
/// 2026-10-22 recipe, Instagram's dark frost (Marracat's tab bar): a blur with
/// a dark tint about 85% strong and a light rim along the top edge.
enum DarkGlass {
    static let ink = Color(red: 40 / 255, green: 44 / 255, blue: 48 / 255)
    static let tint = 0.85
    /// How strongly Liquid Glass is tinted dark. Enough that white text on
    /// it passes the contrast audit over a light map, light enough that the
    /// glass still reads as glass.
    static let liquidTint = 0.55
    /// Light along the top edge, fading down: the glass catching light.
    static let rim = LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.05)],
                                    startPoint: .top, endPoint: .bottom)
    /// The selected tab's pill: a lighter frosted grey.
    static let pill = LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.13)],
                                     startPoint: .top, endPoint: .bottom)
}

extension View {
    @ViewBuilder
    func darkGlass<S: InsettableShape>(in shape: S, shadow: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            // Liquid Glass draws its own edge light and depth; no rim or
            // shadow on top. Dark scheme so its highlights suit the tint.
            glassEffect(.regular.tint(DarkGlass.ink.opacity(DarkGlass.liquidTint)), in: shape)
                .environment(\.colorScheme, .dark)
        } else {
            frostedDarkGlass(in: shape, shadow: shadow)
        }
    }

    /// The pre-iOS 26 recipe.
    private func frostedDarkGlass<S: InsettableShape>(in shape: S, shadow: Bool) -> some View {
        background {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(DarkGlass.ink.opacity(DarkGlass.tint))
            }
            .environment(\.colorScheme, .dark)
        }
        .overlay(shape.strokeBorder(DarkGlass.rim, lineWidth: 1))
        .shadow(color: .black.opacity(shadow ? 0.35 : 0), radius: 14, y: 6)
    }
}

import SwiftUI

/// Instagram's dark frost (owner, 2026-10-22, "lets do the dark glass" after
/// divinedavis.com/previews/#Milepost), the same recipe as Marracat's tab
/// bar: a blur with a dark tint about 85% strong on top, so the map or the
/// list shows through only faintly, and a light rim along the top edge.
/// Material + tint rather than iOS 26's glassEffect, so it looks the same on
/// every iOS Milepost supports (17+).
enum DarkGlass {
    static let ink = Color(red: 40 / 255, green: 44 / 255, blue: 48 / 255)
    static let tint = 0.85
    /// Light along the top edge, fading down: the glass catching light.
    static let rim = LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.05)],
                                    startPoint: .top, endPoint: .bottom)
    /// The selected tab's pill: a lighter frosted grey.
    static let pill = LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.13)],
                                     startPoint: .top, endPoint: .bottom)
}

extension View {
    func darkGlass<S: InsettableShape>(in shape: S, shadow: Bool = true) -> some View {
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

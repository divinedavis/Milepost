import SwiftUI
import UIKit

/// The cold-launch splash, in the spirit of Netflix's: the wordmark builds
/// letter by letter on black, holds a beat, then cross-fades into the app.
///
/// It picks up exactly where the static launch screen leaves off. The launch
/// screen is the runner M (`LaunchLogo`) centred on `LaunchBackground`; this
/// view draws the same M at the same place and size on the same colour, so
/// the hand-off is invisible. The M then slides left as I‑L‑E‑P‑O‑S‑T unfold
/// to its right, matching `scripts/make_wordmark.py` glyph for glyph (Arial
/// Rounded Bold caps, 12° skew, the M as a striding runner).
///
/// Everything is vector, drawn in `Canvas` from a `TimelineView` clock, so
/// there is no per-letter state and a dropped frame cannot desynchronise the
/// letters. Reduce Motion skips the choreography and just fades.
struct LaunchSplashView: View {
    /// Called once when the letters have all landed and the wordmark is
    /// holding. The owner mounts the app underneath at this point, not
    /// before: laying out the Record tab's map blocks the main thread for
    /// most of a second, and while it is blocked nothing here draws. Mounted
    /// under the hold, the stall just lengthens the hold; mounted at start,
    /// it swallowed the whole choreography and the wordmark popped in.
    let onReveal: () -> Void
    /// Called once when the fade-out has finished; the owner removes the view.
    let onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Seconds of *rendered* time. Each frame adds the real gap since the
    /// last one, capped at a frame's worth, so a main-thread stall pauses the
    /// choreography instead of skipping it. A wall clock started on appear
    /// had the whole thing over before the first frame drew (the App body
    /// runs a second before the launch screen fades), and one that survived
    /// that still lost the fade to the stall the app mount causes.
    @State private var clock: TimeInterval = 0
    @State private var lastTick: Date?
    @State private var revealed = false
    @State private var finished = false

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas(rendersAsynchronously: false) { context, size in
                Splash.draw(in: &context, size: size, time: clock, reduceMotion: reduceMotion)
            }
            .onChange(of: timeline.date, initial: true) { _, now in
                if let last = lastTick {
                    clock += min(now.timeIntervalSince(last), Splash.maxFrameStep)
                }
                lastTick = now
                if clock >= Splash.revealAt, !revealed {
                    revealed = true
                    onReveal()
                }
                if clock >= Splash.total, !finished {
                    finished = true
                    onFinished()
                }
            }
        }
        .background(Theme.launchBackground)
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Milepost")
        .accessibilityIdentifier("splash")
    }

    /// Off under `-uitest` (every test would pay two seconds per launch)
    /// unless a test asks for it with `-uitest-splash`.
    static var isEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        return !args.contains("-uitest") || args.contains("-uitest-splash")
    }
}

/// The drawing, in the wordmark's own units (cap height 100) so it is a
/// straight port of `make_wordmark.py`.
enum Splash {
    // MARK: Timeline (seconds of rendered time from the first frame)
    /// A gap between frames longer than this counts as a stall, not as time.
    static let maxFrameStep = 1.0 / 20
    /// The M sits where the launch screen left it until the system's own
    /// cross-fade from the launch snapshot has finished; moving earlier
    /// leaves a ghost M behind.
    static let holdLaunchPose = 0.55
    static let moveDuration = 0.40
    static let letterStart = holdLaunchPose + 0.15
    static let letterStagger = 0.06
    static let letterDuration = 0.30
    /// The last letter has landed; the app mounts underneath from here.
    static let revealAt = letterStart + letterStagger * Double(letters.count - 1) + letterDuration
    static let fadeStart = revealAt + 0.40
    static let fadeDuration = 0.35
    static let total = fadeStart + fadeDuration

    // MARK: Geometry, from make_wordmark.py
    static let cap: CGFloat = 100
    static let stroke: CGFloat = 20
    static let skew = tan(-12 * CGFloat.pi / 180)
    static let letters = Array("ILEPOST")
    static let tracking: CGFloat = -6
    /// Arial Rounded Bold's cap height is 1491/2048 em.
    static let fontSize = cap * 2048 / 1491
    /// The advance of the runner M plus the gap before the I.
    static let mAdvance: CGFloat = 108 + 10
    /// The runner's toe (and its round cap) reaches this far left of the M's
    /// origin, so the ink starts before x = 0.
    static let legOverhang: CGFloat = 38 + stroke / 2

    // The static launch screen: `LaunchLogo` is 144 x 120 pt, the `mark()`
    // viewBox (180 x 150 units) at 0.8 pt per unit, centred on screen.
    static let launchScale: CGFloat = 0.8
    static let launchBox = CGSize(width: 180, height: 150)
    static let launchM = CGPoint(x: 60, y: 124)     // M origin, baseline in mark()

    static let unbounded = CGSize(width: CGFloat.infinity, height: CGFloat.infinity)
    static let ink = Color.white
    static let accent = Theme.accent

    static func draw(in context: inout GraphicsContext, size: CGSize, time: TimeInterval, reduceMotion: Bool) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let font = Self.font
        let glyphs = letters.map { context.resolve(Text(String($0)).font(font).foregroundStyle(ink)) }
        let advances = glyphs.map { $0.measure(in: Splash.unbounded).width }
        let wordWidth = mAdvance + advances.reduce(0, +) + tracking * CGFloat(letters.count - 1)
        // The ink box: from the toe to the T, plus the lean of the tops
        // (cap * tan 12°) the skew adds on the right.
        let inkWidth = legOverhang + wordWidth + cap * -skew

        // Final pose: the ink centred, at most 86% of the width.
        let finalScale = min(launchScale, size.width * 0.86 / inkWidth)
        let finalOrigin = CGPoint(x: centre.x - inkWidth * finalScale / 2 + legOverhang * finalScale,
                                  y: centre.y + cap * finalScale / 2)   // baseline
        let launchOrigin = CGPoint(x: centre.x - launchBox.width * launchScale / 2 + launchM.x * launchScale,
                                   y: centre.y - launchBox.height * launchScale / 2 + launchM.y * launchScale)
        // mark() skews about the viewBox top, not the baseline: at the
        // baseline that is a shift of baseline * tan(-12°).
        let launchM = CGAffineTransform(translationX: launchOrigin.x + launchM.y * launchScale * skew, y: launchOrigin.y)
            .scaledBy(x: launchScale, y: launchScale)
        let finalM = CGAffineTransform(translationX: finalOrigin.x, y: finalOrigin.y)
            .scaledBy(x: finalScale, y: finalScale)

        let move = reduceMotion ? 1 : easeInOut(progress(time, from: holdLaunchPose, duration: moveDuration))
        let fade = 1 - easeInOut(progress(time, from: fadeStart, duration: fadeDuration))
        context.opacity = fade

        // The runner M, interpolated between the launch pose and its place
        // in the word. Both transforms are translate·scale, so a linear blend
        // of the components is exactly a linear blend of the poses.
        var m = context
        m.concatenate(lerp(launchM, finalM, move).skewedAboutBaseline())
        drawRunnerM(in: &m)

        // The letters, unfolding left to right from their own left edge.
        var pen = mAdvance
        for (i, glyph) in glyphs.enumerated() {
            let p = reduceMotion
                ? easeInOut(progress(time, from: holdLaunchPose, duration: moveDuration))
                : easeOut(progress(time, from: letterStart + Double(i) * letterStagger, duration: letterDuration))
            if p > 0 {
                var g = context
                g.concatenate(finalM.skewedAboutBaseline())
                g.translateBy(x: pen, y: 0)
                g.opacity = p * fade
                g.scaleBy(x: reduceMotion ? 1 : 0.25 + 0.75 * p, y: 1)
                g.translateBy(x: 0, y: reduceMotion ? 0 : (1 - p) * 8)
                let bounds = glyph.measure(in: Splash.unbounded)
                let baseline = glyph.firstBaseline(in: bounds)
                g.draw(glyph, at: CGPoint(x: 0, y: -baseline), anchor: .topLeading)
            }
            pen += advances[i] + tracking
        }
    }

    /// `runner_m()`: the M is a monoline path whose left stem is a trailing
    /// leg, bent back at the knee and ending in a foot, in the accent colour.
    static func drawRunnerM(in context: inout GraphicsContext) {
        let top = -cap
        let r = stroke / 2
        let lx: CGFloat = 10, rx: CGFloat = 90
        let hip = CGPoint(x: lx, y: -42)
        let knee = CGPoint(x: lx - 16, y: -6)
        let toe = CGPoint(x: lx - 38, y: -12)

        var leg = Path()
        leg.move(to: hip)
        leg.addLine(to: knee)
        leg.addLine(to: toe)

        var body = Path()
        body.move(to: hip)
        body.addLine(to: CGPoint(x: lx, y: top + r))
        body.addLine(to: CGPoint(x: lx + 40, y: -26))
        body.addLine(to: CGPoint(x: rx, y: top + r))
        body.addLine(to: CGPoint(x: rx, y: -r))

        let style = StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)
        context.stroke(leg, with: .color(accent), style: style)
        context.stroke(body, with: .color(ink), style: style)
    }

    /// Arial Rounded MT Bold ships with iOS; the rounded system face is the
    /// fallback so a missing font degrades to a near match, not to Helvetica.
    static var font: Font {
        if UIFont(name: "ArialRoundedMTBold", size: fontSize) != nil {
            return .custom("ArialRoundedMTBold", fixedSize: fontSize)
        }
        return .system(size: fontSize, weight: .black, design: .rounded)
    }

    // MARK: Easing

    static func progress(_ t: TimeInterval, from start: TimeInterval, duration: TimeInterval) -> CGFloat {
        CGFloat(min(max((t - start) / duration, 0), 1))
    }

    static func easeOut(_ p: CGFloat) -> CGFloat { 1 - pow(1 - p, 3) }

    static func easeInOut(_ p: CGFloat) -> CGFloat {
        p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2
    }

    static func lerp(_ a: CGAffineTransform, _ b: CGAffineTransform, _ t: CGFloat) -> CGAffineTransform {
        CGAffineTransform(a: a.a + (b.a - a.a) * t, b: a.b + (b.b - a.b) * t,
                          c: a.c + (b.c - a.c) * t, d: a.d + (b.d - a.d) * t,
                          tx: a.tx + (b.tx - a.tx) * t, ty: a.ty + (b.ty - a.ty) * t)
    }
}

private extension CGAffineTransform {
    /// The wordmark's italic: `skewX(-12)` applied in glyph space, about the
    /// baseline (y = 0), before this transform's scale and translation.
    func skewedAboutBaseline() -> CGAffineTransform {
        CGAffineTransform(a: 1, b: 0, c: Splash.skew, d: 1, tx: 0, ty: 0).concatenating(self)
    }
}

#Preview {
    LaunchSplashView(onReveal: {}, onFinished: {})
}

import SwiftUI

/// One sport mark across the picker, history, friends and Live Activity.
struct SportIcon: View {
    let sport: Sport
    var size: CGFloat = 17
    var weight: Font.Weight = .regular

    var body: some View {
        Group {
            if let symbol = sport.symbol {
                Image(systemName: symbol)
                    .font(.system(size: size, weight: weight))
            } else {
                StrollerRunner()
                    .fill(.foreground)
                    .frame(width: size * 1.3, height: size)
            }
        }
        .accessibilityLabel(sport.title)
    }
}

/// A forward-leaning runner holding a jogging stroller, in the same solid,
/// rounded style as the walking and running system symbols.
private struct StrollerRunner: Shape {
    func path(in rect: CGRect) -> Path {
        var silhouette = Path()
        silhouette.addEllipse(in: CGRect(x: 12, y: 0, width: 5, height: 5))

        var limbs = Path()
        // Torso and arms, with the forward hand meeting the stroller handle.
        limbs.move(to: CGPoint(x: 12.5, y: 7))
        limbs.addLine(to: CGPoint(x: 9, y: 14))
        limbs.move(to: CGPoint(x: 12, y: 7))
        limbs.addLine(to: CGPoint(x: 15, y: 11))
        limbs.addLine(to: CGPoint(x: 20, y: 11))
        limbs.move(to: CGPoint(x: 11.5, y: 7.5))
        limbs.addLine(to: CGPoint(x: 7.5, y: 7))
        limbs.addLine(to: CGPoint(x: 4.5, y: 10))
        // Running stride: one leg forward, the other kicked back.
        limbs.move(to: CGPoint(x: 9, y: 14))
        limbs.addLine(to: CGPoint(x: 13, y: 18))
        limbs.addLine(to: CGPoint(x: 11, y: 23))
        limbs.move(to: CGPoint(x: 9, y: 14))
        limbs.addLine(to: CGPoint(x: 5, y: 19))
        limbs.addLine(to: CGPoint(x: 1.5, y: 17))
        silhouette.addPath(limbs.strokedPath(StrokeStyle(lineWidth: 2.7, lineCap: .round, lineJoin: .round)))

        var frame = Path()
        frame.move(to: CGPoint(x: 18.5, y: 9))
        frame.addLine(to: CGPoint(x: 20, y: 9))
        frame.addLine(to: CGPoint(x: 24, y: 20))
        frame.addLine(to: CGPoint(x: 29, y: 20))
        frame.move(to: CGPoint(x: 27, y: 15))
        frame.addLine(to: CGPoint(x: 21, y: 21))
        silhouette.addPath(frame.strokedPath(StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round)))

        // Canopy and seat sit above two clearly separated wheels.
        var seat = Path()
        seat.move(to: CGPoint(x: 24, y: 8))
        seat.addQuadCurve(to: CGPoint(x: 30, y: 14), control: CGPoint(x: 30, y: 8))
        seat.addLine(to: CGPoint(x: 21.5, y: 14))
        seat.addQuadCurve(to: CGPoint(x: 28, y: 17), control: CGPoint(x: 23, y: 18))
        seat.addLine(to: CGPoint(x: 30, y: 14))
        seat.addLine(to: CGPoint(x: 24, y: 14))
        seat.closeSubpath()
        silhouette.addPath(seat)
        silhouette.addEllipse(in: CGRect(x: 18.5, y: 20, width: 4, height: 4))
        silhouette.addEllipse(in: CGRect(x: 27, y: 20, width: 4, height: 4))

        return silhouette.applying(CGAffineTransform(scaleX: rect.width / 32, y: rect.height / 24))
            .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}

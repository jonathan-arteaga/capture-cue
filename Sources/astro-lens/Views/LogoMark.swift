import SwiftUI

struct LogoMark: View {
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let side = min(canvasSize.width, canvasSize.height)
            let rect = CGRect(
                x: (canvasSize.width - side) / 2,
                y: (canvasSize.height - side) / 2,
                width: side,
                height: side
            )
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = side * 0.34
            let lineWidth = max(side * 0.16, 3)

            var cPath = Path()
            cPath.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(42),
                endAngle: .degrees(318),
                clockwise: false
            )
            context.stroke(
                cPath,
                with: .color(Color(red: 0.04, green: 0.08, blue: 0.26)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )

            var mintPath = Path()
            mintPath.move(to: CGPoint(x: rect.minX + side * 0.28, y: rect.minY + side * 0.61))
            mintPath.addCurve(
                to: CGPoint(x: rect.minX + side * 0.55, y: rect.minY + side * 0.48),
                control1: CGPoint(x: rect.minX + side * 0.38, y: rect.minY + side * 0.62),
                control2: CGPoint(x: rect.minX + side * 0.41, y: rect.minY + side * 0.48)
            )
            mintPath.addCurve(
                to: CGPoint(x: rect.minX + side * 0.72, y: rect.minY + side * 0.50),
                control1: CGPoint(x: rect.minX + side * 0.62, y: rect.minY + side * 0.48),
                control2: CGPoint(x: rect.minX + side * 0.65, y: rect.minY + side * 0.50)
            )
            context.stroke(
                mintPath,
                with: .color(Color(red: 0.42, green: 0.88, blue: 0.84)),
                style: StrokeStyle(lineWidth: max(side * 0.14, 3), lineCap: .round)
            )

            var bluePath = Path()
            bluePath.move(to: CGPoint(x: rect.minX + side * 0.40, y: rect.minY + side * 0.62))
            bluePath.addCurve(
                to: CGPoint(x: rect.minX + side * 0.78, y: rect.minY + side * 0.51),
                control1: CGPoint(x: rect.minX + side * 0.52, y: rect.minY + side * 0.65),
                control2: CGPoint(x: rect.minX + side * 0.58, y: rect.minY + side * 0.48)
            )
            context.stroke(
                bluePath,
                with: .color(Color(red: 0.02, green: 0.64, blue: 0.86)),
                style: StrokeStyle(lineWidth: max(side * 0.14, 3), lineCap: .round)
            )
        }
        .frame(width: size, height: size)
        .accessibilityLabel("astro-lens")
    }
}

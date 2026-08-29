import SwiftUI

/// The sweeping quadrant of an Academy leader — a wedge from the centre,
/// drawn from twelve o'clock so it reads as a hand starting from the top.
struct LeaderHand: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: centre)
        path.addArc(
            center: centre,
            radius: rect.width / 2,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

import SwiftUI
import FlowScribeCore

/// Faisceaux de lumière depuis un bord (réf. Side Rays) : quelques cônes de gradient flous + shimmer lent.
struct SideRaysView: View {
    @Environment(\.ambiance) private var ambiance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    var surface: AmbianceSurface = .onboarding

    var body: some View {
        let animate = ambiance.animates(surface, reduceMotion: reduceMotion,
                                        windowActive: activeState != .inactive)
        let cols = ambiance.palette.auroraColors
        TimelineView(.animation(minimumInterval: nil, paused: !animate)) { tl in
            let t = animate ? tl.date.timeIntervalSinceReferenceDate : 0
            Canvas { ctx, size in
                let origin = CGPoint(x: size.width * 0.08, y: -size.height * 0.1)
                for i in 0..<4 {
                    let base = Double(i) * 18 - 10
                    let sweep = base + 6 * sin(t * 0.5 + Double(i))
                    let len = size.height * 1.4
                    let a = Angle(degrees: sweep).radians
                    let spread = 0.06
                    var path = Path()
                    path.move(to: origin)
                    path.addLine(to: CGPoint(x: origin.x + len * sin(a - spread), y: origin.y + len * cos(a - spread)))
                    path.addLine(to: CGPoint(x: origin.x + len * sin(a + spread), y: origin.y + len * cos(a + spread)))
                    path.closeSubpath()
                    let c = cols[i % cols.count].opacity(0.10 + 0.05 * sin(t + Double(i)))
                    ctx.fill(path, with: .color(c))
                }
            }
            .blur(radius: 30)
        }
        .allowsHitTesting(false)
    }
}

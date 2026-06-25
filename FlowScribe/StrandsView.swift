import SwiftUI
import FlowScribeCore

/// Fils lumineux qui ondulent (motif signature). Généralise le rendu du HUD pour un usage plein écran.
struct StrandsView: View {
    @Environment(\.ambiance) private var ambiance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    var lineCount: Int = 6
    var amplitude: Double = 0.5        // 0…1 (au repos : pas de micro, ondulation douce)
    var speed: Double = 1
    var surface: AmbianceSurface = .appWindow

    var body: some View {
        let animate = ambiance.animates(surface, reduceMotion: reduceMotion,
                                        windowActive: activeState != .inactive)
        let cols = ambiance.palette.auroraColors
        TimelineView(.animation(minimumInterval: nil, paused: !animate)) { tl in
            let t = animate ? tl.date.timeIntervalSinceReferenceDate * speed : 0
            Canvas { ctx, size in
                let w = Double(size.width), h = Double(size.height)
                let midY = h / 2, maxSwing = h * 0.42, steps = 96
                for j in 0..<lineCount {
                    let phase = Double(j) * 0.7
                    let dir: Double = (j % 2 == 0) ? 1 : -1
                    let freq = 1.6 + Double(j) * 0.18
                    let amp = maxSwing * (0.16 + 0.84 * amplitude) * (1.0 - 0.06 * Double(j))
                    let k1 = 2 * Double.pi * freq, k2 = Double.pi * freq
                    let travel1 = dir * t * 1.7 + phase, travel2 = (-dir) * t * 1.1 + phase * 1.3
                    var path = Path()
                    for s in 0...steps {
                        let xN = Double(s) / Double(steps)
                        let envelope = sin(Double.pi * xN)
                        let wave = sin(k1 * xN + travel1) + 0.35 * sin(k2 * xN + travel2)
                        let yOffset = envelope * amp * wave
                        let pt = CGPoint(x: CGFloat(xN * w), y: CGFloat(midY - yOffset))
                        if s == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                    let depth = Double(j) / Double(max(1, lineCount - 1))
                    let color = cols[j % cols.count].opacity((0.5 - 0.35 * depth))
                    ctx.stroke(path, with: .color(color), lineWidth: CGFloat(1.8 - 0.12 * Double(j)))
                }
            }
            // Fondu transparent doux sur les bords (ends souples, pas de cassure nette).
            .mask(LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: 0.06),
                .init(color: .black, location: 0.94),
                .init(color: .clear, location: 1.0),
            ], startPoint: .leading, endPoint: .trailing))
        }
        .allowsHitTesting(false)
    }
}

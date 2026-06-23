import SwiftUI
import FlowScribeCore

@MainActor
@Observable
final class HUDModel {
    var state: DictationState = .idle
    var level: Double = 0
}

struct LiveHUDView: View {
    let model: HUDModel

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                // Teinte sombre translucide (foncé, mais on voit à travers).
                Theme.glassTint
                // Lueur bleue qui dérive lentement.
                RadialGradient(colors: [Theme.glowColor.opacity(0.40), .clear],
                               center: UnitPoint(x: 0.5 + 0.25 * cos(t * 0.6),
                                                 y: 0.5 + 0.25 * sin(t * 0.8)),
                               startRadius: 2, endRadius: 120)
                // Barres d'égaliseur : montent/descendent selon le niveau de voix.
                Canvas { ctx, size in
                    let bars = 7
                    let barW: CGFloat = 5
                    let gap: CGFloat = 6
                    let totalW = CGFloat(bars) * barW + CGFloat(bars - 1) * gap
                    let startX = (size.width - totalW) / 2
                    let midY = size.height / 2
                    let maxH = size.height * 0.66
                    let recording = model.state == .recording
                    for i in 0..<bars {
                        let osc = 0.5 + 0.5 * sin(t * 6 + Double(i) * 0.7)
                        let lvl = recording ? model.level : 0.0
                        let frac = min(1.0, 0.18 + lvl * osc)
                        let h = max(5, maxH * CGFloat(frac))
                        let x = startX + CGFloat(i) * (barW + gap)
                        let rect = CGRect(x: x, y: midY - h / 2, width: barW, height: h)
                        ctx.fill(Path(roundedRect: rect, cornerRadius: barW / 2), with: .color(Theme.sky))
                    }
                }
            }
            .frame(width: 240, height: 56)
            .clipShape(Capsule())
            .glassEffect(.clear, in: .capsule)
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        }
    }
}

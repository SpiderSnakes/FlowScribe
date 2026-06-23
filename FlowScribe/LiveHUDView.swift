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
                // Teinte sombre très légère (lisibilité sur fond clair, sans casser la transparence).
                Theme.glassTint
                // Lueur bleue qui dérive lentement.
                RadialGradient(colors: [Theme.glowColor.opacity(0.45), .clear],
                               center: UnitPoint(x: 0.5 + 0.30 * cos(t * 0.6),
                                                 y: 0.5 + 0.30 * sin(t * 0.8)),
                               startRadius: 2, endRadius: 130)
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    let base = min(size.width, size.height) / 2
                    let recording = model.state == .recording
                    let amp = recording ? (0.25 + 0.75 * model.level) : 0.12
                    for i in 0..<3 {
                        let phase = (t * 0.8 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        let r = base * (0.3 + phase * 0.9 * amp)
                        let opacity = (1 - phase) * (recording ? 0.9 : 0.35)
                        let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
                        ctx.stroke(Path(ellipseIn: rect), with: .color(Theme.sky.opacity(opacity)), lineWidth: 2)
                    }
                    let breath = 0.5 + 0.5 * sin(t * 2)
                    let coreR = base * (recording ? (0.18 + 0.16 * model.level) : (0.16 + 0.04 * breath))
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - coreR, y: c.y - coreR, width: 2 * coreR, height: 2 * coreR)),
                             with: .color(Theme.sky))
                }
            }
        }
        .frame(width: 260, height: 64)
        .glassEffect(.clear, in: .capsule)
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

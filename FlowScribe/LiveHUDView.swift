import SwiftUI
import FlowScribeCore

@MainActor
@Observable
final class HUDModel {
    var state: DictationState = .idle
    var level: Double = 0
    /// Historique des niveaux (buffer circulaire) pour la waveform pleine largeur.
    var levels: [Double] = Array(repeating: 0, count: 64)

    func pushLevel(_ v: Double) {
        let clamped = max(0, min(1, v))
        level = clamped
        levels.removeFirst()
        levels.append(clamped)
    }

    func resetLevels() {
        level = 0
        levels = Array(repeating: 0, count: levels.count)
    }
}

struct LiveHUDView: View {
    let model: HUDModel

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let bars = 9
                let barW: CGFloat = 5
                let gap: CGFloat = 7
                let totalW = CGFloat(bars) * barW + CGFloat(bars - 1) * gap
                let startX = (size.width - totalW) / 2
                let midY = size.height / 2
                let maxH = size.height * 0.82
                let recording = model.state == .recording
                for i in 0..<bars {
                    let gained = recording ? HUDWaveform.gain(model.level) : 0.0
                    let shimmer = 0.85 + 0.15 * sin(t * 5.0 + Double(i) * 0.6)
                    let idle = 0.12 + 0.07 * sin(t * 2.2 + Double(i) * 0.45)
                    let frac = max(idle, gained * shimmer)
                    let h = max(4, maxH * CGFloat(frac))
                    let x = startX + CGFloat(i) * (barW + gap)
                    let rect = CGRect(x: x, y: midY - h / 2, width: barW, height: h)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barW / 2), with: .color(HUDWaveform.barColor(frac: frac)))
                }
            }
            .frame(width: 240, height: 56)
            .background(Theme.hudPanelFill, in: Capsule())
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
        }
    }
}

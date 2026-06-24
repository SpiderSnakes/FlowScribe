import SwiftUI
import FlowScribeCore

@MainActor
@Observable
final class HUDModel {
    var state: DictationState = .idle
    /// Niveau micro lissé (0…1), interpolé à ~60fps vers la dernière mesure — c'est ce que lisent les vues.
    /// Le micro n'envoie qu'~10 mesures/s ; sans ce lissage la waveform « saute » (saccades).
    private(set) var level: Double = 0

    private var target: Double = 0
    private var timer: Timer?

    /// Mesure brute du micro (~10 Hz) : on ne fait que poser la cible ; le lissage tourne à 60fps.
    func pushLevel(_ v: Double) {
        target = max(0, min(1, v))
        startTicking()
    }

    func resetLevels() {
        target = 0
        level = 0
    }

    /// Arrête net l'animation (HUD masqué) pour ne pas laisser tourner le timer.
    func stop() {
        target = 0; level = 0
        timer?.invalidate(); timer = nil
    }

    private func startTicking() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // mode .common : continue d'animer pendant le suivi d'événements (menus, scroll) — sinon la waveform fige.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        if state != .recording { target = 0 }          // plus de capture → la waveform retombe en douceur
        let rate = target > level ? 0.35 : 0.12         // attaque vive, relâchement doux → organique
        level += (target - level) * rate
        if abs(target - level) < 0.0015 {
            level = target
            if state != .recording { timer?.invalidate(); timer = nil }
        }
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
                let level = recording ? HUDWaveform.gain(model.level) : 0.0   // lu une fois par frame (cohérence)
                for i in 0..<bars {
                    let gained = level
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

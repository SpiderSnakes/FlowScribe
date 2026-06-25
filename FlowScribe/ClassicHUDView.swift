import SwiftUI
import FlowScribeCore

/// HUD « Classic » (réf. SuperWhisper) : barre large sombre, waveform pleine largeur
/// vivante (60fps, gain + shimmer + respiration au repos) + rappel des raccourcis.
struct ClassicHUDView: View {
    let model: HUDModel
    @Environment(\.ambiance) private var ambiance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            waveform
                .frame(height: 56)
                .padding(.horizontal, 16)
            Divider().overlay(Theme.hairline)
            controls
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
        .frame(width: 380)
        .background(Theme.hudPanelFill, in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
        .borderGlow(active: model.state == .recording, cornerRadius: 18)
    }

    /// Maillage dense de lignes horizontales sinueuses : chaque ligne a sa propre phase/fréquence/
    /// amplitude/vitesse (pseudo-aléatoire déterministe → organique mais stable, sans scintillement).
    /// Au repos elles ondulent doucement ; quand on parle, l'amplitude gonfle vers le centre.
    private let lineCount = 18

    /// Hash déterministe → 0…1. Pas de Date/random : reproductible à chaque frame (aucun jitter).
    private func rnd(_ seed: Int, _ salt: Int) -> Double {
        let x = sin(Double(seed) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return x - floor(x)
    }

    private var waveform: some View {
        let animate = ambiance.animates(.hud, reduceMotion: reduceMotion, windowActive: true)
        return TimelineView(.animation(minimumInterval: nil, paused: !animate)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let level = HUDWaveform.gain(model.level)
                let w = Double(size.width)
                let h = Double(size.height)
                let midY = h / 2
                let maxSwing = h * 0.46
                let steps = 64
                for j in 0..<lineCount {
                    let phase: Double = rnd(j, 1) * 6.283
                    let dir: Double = (j % 2 == 0) ? 1 : -1
                    let freq: Double = 1.3 + rnd(j, 2) * 1.7                       // 1.3…3.0, désordonné
                    let amp: Double = maxSwing * (0.10 + 0.90 * level) * (0.55 + 0.45 * rnd(j, 3))
                    let harm: Double = 0.25 + rnd(j, 4) * 0.45                      // ratio d'harmonique
                    let sp1: Double = 2.6 + rnd(j, 5) * 2.0                         // défilement plus rapide
                    let sp2: Double = 1.7 + rnd(j, 6) * 1.4
                    let breath: Double = 0.82 + 0.18 * sin(t * (0.4 + rnd(j, 7)) + phase)   // respiration lente par ligne
                    let k1: Double = 2 * Double.pi * freq
                    let k2: Double = Double.pi * freq
                    let travel1: Double = dir * t * sp1 + phase
                    let travel2: Double = (-dir) * t * sp2 + phase * 1.3
                    var path = Path()
                    for s in 0...steps {
                        let xN: Double = Double(s) / Double(steps)
                        let envelope: Double = sin(Double.pi * xN)   // 0 aux bords, 1 au centre → « monte vers le milieu »
                        let primary: Double = sin(k1 * xN + travel1)
                        let secondary: Double = sin(k2 * xN + travel2)
                        let wave: Double = (primary + harm * secondary) * breath
                        let yOffset: Double = envelope * amp * wave
                        let point = CGPoint(x: CGFloat(xN * w), y: CGFloat(midY - yOffset))
                        if s == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    ctx.stroke(path,
                               with: .color(HUDWaveform.lineColor(index: j, of: lineCount, level: level, accents: ambiance.palette.auroraColors)),
                               lineWidth: CGFloat(1.4 - 0.04 * Double(j)))
                }
            }
            // Fondu transparent doux sur les bords G/D (plus de cassure nette).
            .mask(LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1.0),
            ], startPoint: .leading, endPoint: .trailing))
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.sky)
            Spacer()
            shortcutHint(label: "Stop", keys: ["⌥", "Espace"])
            shortcutHint(label: "Annuler", keys: ["esc"])
        }
        .font(.system(size: 11))
    }

    private func shortcutHint(label: String, keys: [String]) -> some View {
        HStack(spacing: 5) {
            Text(label).foregroundStyle(.secondary)
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

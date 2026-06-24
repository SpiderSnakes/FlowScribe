import SwiftUI
import FlowScribeCore

/// HUD « Classic » (réf. SuperWhisper) : barre large sombre, waveform pleine largeur
/// vivante (60fps, gain + shimmer + respiration au repos) + rappel des raccourcis.
struct ClassicHUDView: View {
    let model: HUDModel
    @Environment(\.ambiance) private var ambiance

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

    /// Maillage de lignes horizontales sinueuses (gris/blanc, opacités dégradées) : au repos
    /// elles ondulent doucement ; quand on parle, l'amplitude gonfle vers le centre. Tout est
    /// dérivé du temps continu + du niveau lissé → fluide, organique, sans saccade.
    private let lineCount = 6

    private var waveform: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let level = HUDWaveform.gain(model.level)
                let w = Double(size.width)
                let h = Double(size.height)
                let midY = h / 2
                let maxSwing = h * 0.42
                let steps = 72
                for j in 0..<lineCount {
                    let phase: Double = Double(j) * 0.7
                    let dir: Double = (j % 2 == 0) ? 1 : -1
                    let freq: Double = 1.6 + Double(j) * 0.18
                    let amp: Double = maxSwing * (0.16 + 0.84 * level) * (1.0 - 0.06 * Double(j))
                    // Constantes hoistées hors de la boucle (indépendantes de `s`) : type-check + perf.
                    let k1: Double = 2 * Double.pi * freq
                    let k2: Double = Double.pi * freq
                    let travel1: Double = dir * t * 1.7 + phase
                    let travel2: Double = (-dir) * t * 1.1 + phase * 1.3
                    var path = Path()
                    for s in 0...steps {
                        let xN: Double = Double(s) / Double(steps)
                        let envelope: Double = sin(Double.pi * xN)   // 0 aux bords, 1 au centre → « monte vers le milieu »
                        let primary: Double = sin(k1 * xN + travel1)
                        let secondary: Double = sin(k2 * xN + travel2)
                        let wave: Double = primary + 0.35 * secondary
                        let yOffset: Double = envelope * amp * wave
                        let point = CGPoint(x: CGFloat(xN * w), y: CGFloat(midY - yOffset))
                        if s == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    ctx.stroke(path,
                               with: .color(HUDWaveform.lineColor(index: j, of: lineCount, level: level, accents: ambiance.palette.auroraColors)),
                               lineWidth: CGFloat(1.8 - 0.12 * Double(j)))
                }
            }
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

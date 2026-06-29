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
    private let steps = 64

    /// Constantes déterministes d'une ligne (ne dépendent que de `j`) : précalculées UNE fois
    /// au lieu d'être recalculées via rnd() à chaque frame (60 fps → 7560 appels/s évités).
    private struct LineParams {
        let phase, dir, freq, harm, sp1, sp2, breathRate, ampRnd, k1, k2, lineWidth: Double
    }

    /// Hash déterministe → 0…1. Pas de Date/random : reproductible (aucun jitter).
    private static func rnd(_ seed: Int, _ salt: Int) -> Double {
        let x = sin(Double(seed) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return x - floor(x)
    }

    /// Table figée des 18 lignes : calculée une seule fois pour tout le type (et plus à chaque frame).
    private static let lines: [LineParams] = (0..<18).map { j in
        let phase = rnd(j, 1) * 6.283
        let dir: Double = (j % 2 == 0) ? 1 : -1
        let freq = 1.3 + rnd(j, 2) * 1.7                       // 1.3…3.0, désordonné
        return LineParams(
            phase: phase, dir: dir, freq: freq,
            harm: 0.25 + rnd(j, 4) * 0.45,                      // ratio d'harmonique
            sp1: 2.6 + rnd(j, 5) * 2.0,                         // défilement plus rapide
            sp2: 1.7 + rnd(j, 6) * 1.4,
            breathRate: 0.4 + rnd(j, 7),
            ampRnd: 0.55 + 0.45 * rnd(j, 3),
            k1: 2 * Double.pi * freq, k2: Double.pi * freq,
            lineWidth: 1.4 - 0.04 * Double(j))
    }

    private var waveform: some View {
        let animate = ambiance.animates(.hud, reduceMotion: reduceMotion, windowActive: true)
        // En silence (niveau ~0) on n'a besoin que de la respiration lente : ~15 fps suffisent
        // (économie d'énergie sur portable). Dès qu'on parle, on repasse au taux d'affichage.
        let interval: Double? = model.level < 0.02 ? 1.0 / 15.0 : nil
        return TimelineView(.animation(minimumInterval: interval, paused: !animate)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let level = HUDWaveform.gain(model.level)
                let w = Double(size.width)
                let h = Double(size.height)
                let midY = h / 2
                let maxSwing = h * 0.46
                let accents = ambiance.palette.auroraColors   // lu une fois, plus dans la boucle (évite 18 allocs/frame)
                for j in 0..<lineCount {
                    let p = Self.lines[j]
                    let amp: Double = maxSwing * (0.10 + 0.90 * level) * p.ampRnd
                    let breath: Double = 0.82 + 0.18 * sin(t * p.breathRate + p.phase)   // respiration lente par ligne
                    let travel1: Double = p.dir * t * p.sp1 + p.phase
                    let travel2: Double = (-p.dir) * t * p.sp2 + p.phase * 1.3
                    var path = Path()
                    for s in 0...steps {
                        let xN: Double = Double(s) / Double(steps)
                        let envelope: Double = sin(Double.pi * xN)   // 0 aux bords, 1 au centre → « monte vers le milieu »
                        let primary: Double = sin(p.k1 * xN + travel1)
                        let secondary: Double = sin(p.k2 * xN + travel2)
                        let wave: Double = (primary + p.harm * secondary) * breath
                        let yOffset: Double = envelope * amp * wave
                        let point = CGPoint(x: CGFloat(xN * w), y: CGFloat(midY - yOffset))
                        if s == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    ctx.stroke(path,
                               with: .color(HUDWaveform.lineColor(index: j, of: lineCount, level: level, accents: accents)),
                               lineWidth: CGFloat(p.lineWidth))
                }
            }
            // Fondu transparent doux sur les bords G/D (plus de cassure nette).
            .mask(LinearGradient(stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1.0),
            ], startPoint: .leading, endPoint: .trailing))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Niveau micro")
            .accessibilityValue(model.state == .recording ? "Enregistrement en cours" : "En attente")
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
        // VoiceOver lit les glyphes bruts (⌥, esc) de façon illisible : on expose un libellé parlé propre,
        // tout en gardant les puces visuelles intactes.
        let spoken = label + " : " + keys.map(Self.spokenKey).joined(separator: " ")
        return HStack(spacing: 5) {
            Text(label).foregroundStyle(.secondary)
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// Glyphe/abréviation → nom prononçable en français pour VoiceOver.
    private static func spokenKey(_ key: String) -> String {
        switch key {
        case "⌥": return "Option"
        case "⌘": return "Commande"
        case "⇧": return "Majuscule"
        case "⌃": return "Contrôle"
        case "esc": return "Échap"
        default: return key
        }
    }
}

import SwiftUI
import FlowScribeCore

/// HUD « Classic » (réf. SuperWhisper) : barre large sombre, waveform pleine largeur
/// vivante (60fps, gain + shimmer + respiration au repos) + rappel des raccourcis.
struct ClassicHUDView: View {
    let model: HUDModel
    /// Fond quasi opaque très sombre → fort contraste avec les barres claires.
    private let panelFill = Color(red: 0.03, green: 0.05, blue: 0.10).opacity(0.92)

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
        .background(panelFill, in: RoundedRectangle(cornerRadius: 18))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.hairline, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
    }

    private var waveform: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let levels = model.levels
                let n = levels.count
                guard n > 0 else { return }
                let slot = size.width / CGFloat(n)
                let barW = max(2.5, slot * 0.55)
                let midY = size.height / 2
                let maxH = size.height
                for i in 0..<n {
                    let lvl = levels[i]
                    // Gain : remonte la parole douce (RMS faible) avec une courbe douce.
                    let gained = min(1.0, pow(lvl, 0.55) * 2.6)
                    // Shimmer organique + légère respiration quand c'est calme.
                    let shimmer = 0.85 + 0.15 * sin(t * 5.0 + Double(i) * 0.55)
                    let idle = 0.10 + 0.06 * sin(t * 2.2 + Double(i) * 0.40)
                    let frac = max(idle, gained * shimmer)
                    let h = max(3, maxH * CGFloat(frac))
                    let x = CGFloat(i) * slot + (slot - barW) / 2
                    let rect = CGRect(x: x, y: midY - h / 2, width: barW, height: h)
                    // Contraste : plus fort = plus lumineux (gris clair → blanc), pointe bleutée.
                    let bright = 0.22 + 0.66 * frac
                    let color = Color(red: 0.70 + 0.30 * frac, green: 0.80 + 0.18 * frac, blue: 1.0)
                        .opacity(bright)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: barW / 2), with: .color(color))
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

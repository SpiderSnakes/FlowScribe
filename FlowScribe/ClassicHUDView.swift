import SwiftUI
import FlowScribeCore

/// HUD « Classic » (réf. SuperWhisper) : barre large, waveform pleine largeur
/// alimentée par le vrai niveau micro, + rappel des raccourcis.
struct ClassicHUDView: View {
    let model: HUDModel

    var body: some View {
        VStack(spacing: 0) {
            waveform
                .frame(height: 52)
                .padding(.horizontal, 16)
            Divider().overlay(Theme.hairline)
            controls
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
        .frame(width: 380)
        .background(Theme.glassTint, in: RoundedRectangle(cornerRadius: 18))
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var waveform: some View {
        Canvas { ctx, size in
            let levels = model.levels
            guard !levels.isEmpty else { return }
            let n = levels.count
            let slot = size.width / CGFloat(n)
            let barW = max(2, slot * 0.6)
            let midY = size.height / 2
            let maxH = size.height * 0.92
            for i in 0..<n {
                let lvl = levels[i]
                let h = max(2, maxH * CGFloat(0.06 + 0.94 * lvl))
                let x = CGFloat(i) * slot + (slot - barW) / 2
                let rect = CGRect(x: x, y: midY - h / 2, width: barW, height: h)
                let opacity = 0.30 + 0.70 * lvl
                ctx.fill(Path(roundedRect: rect, cornerRadius: barW / 2),
                         with: .color(Theme.sky.opacity(opacity)))
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
                    .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

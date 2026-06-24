import SwiftUI

/// Calculs partagés par les deux HUD (Classic + Mini) : gain et couleur des barres.
enum HUDWaveform {
    /// Remonte la parole douce (RMS faible) avec une courbe douce, borné à 1.
    static func gain(_ level: Double) -> Double { min(1.0, pow(level, 0.55) * 2.6) }

    /// Barre claire (gris → blanc, pointe bleutée) ; plus fort = plus lumineux. (HUD Mini)
    static func barColor(frac: Double) -> Color {
        Color(red: 0.70 + 0.30 * frac, green: 0.80 + 0.18 * frac, blue: 1.0)
            .opacity(0.22 + 0.66 * frac)
    }

    /// Lignes du maillage (HUD Classic) : gris/blanc légèrement bleuté, l'arrière-plan plus
    /// foncé et translucide, l'avant plus clair ; tout devient plus net quand on parle.
    static func lineColor(index j: Int, of count: Int, level: Double) -> Color {
        let depth = Double(j) / Double(max(1, count - 1))   // 0 (devant) … 1 (fond)
        let opacity = (0.55 - 0.40 * depth) * (0.55 + 0.45 * level)
        let w = 0.92 - 0.20 * depth
        return Color(red: w, green: w, blue: min(1.0, w + 0.06)).opacity(opacity)
    }
}

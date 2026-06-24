import SwiftUI

/// Calculs partagés par les deux HUD (Classic + Mini) : gain et couleur des barres.
enum HUDWaveform {
    /// Remonte la parole douce (RMS faible) avec une courbe douce, borné à 1.
    static func gain(_ level: Double) -> Double { min(1.0, pow(level, 0.55) * 2.6) }

    /// Barre claire (gris → blanc, pointe bleutée) ; plus fort = plus lumineux.
    static func barColor(frac: Double) -> Color {
        Color(red: 0.70 + 0.30 * frac, green: 0.80 + 0.18 * frac, blue: 1.0)
            .opacity(0.22 + 0.66 * frac)
    }
}

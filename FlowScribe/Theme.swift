import SwiftUI
import FlowScribeCore

enum Theme {
    static let deepNight = Color(red: 0.02, green: 0.05, blue: 0.14)
    static let midnight  = Color(red: 0.05, green: 0.10, blue: 0.24)
    static let sky       = Color(red: 0.44, green: 0.64, blue: 0.86)   // bleu adouci (moins électrique)
    /// Accent statique de repli (= palette par défaut). Les vues « brand » lisent plutôt `\.ambiance`.
    static let accent    = AmbiancePalette.nuitBleue.colors.accentPrimary.color

    static let backgroundGradient = LinearGradient(
        colors: [deepNight, midnight],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let glowColor = sky
    /// Bordure fine (style Raycast) sur le verre.
    static let hairline = Color.white.opacity(0.14)
    /// Teinte sombre translucide du HUD (foncé mais on voit à travers).
    static let glassTint = deepNight.opacity(0.45)
    /// Fond quasi opaque très sombre du HUD d'enregistrement (fort contraste avec les barres).
    static let hudPanelFill = Color(red: 0.03, green: 0.05, blue: 0.10).opacity(0.92)
}

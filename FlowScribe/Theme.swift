import SwiftUI

enum Theme {
    static let deepNight = Color(red: 0.02, green: 0.05, blue: 0.14)
    static let midnight  = Color(red: 0.05, green: 0.10, blue: 0.24)
    static let sky       = Color(red: 0.40, green: 0.70, blue: 0.98)
    static let accent    = sky

    static let backgroundGradient = LinearGradient(
        colors: [deepNight, midnight],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let glowColor = sky
    /// Bordure fine (style Raycast) sur le verre.
    static let hairline = Color.white.opacity(0.14)
    /// Teinte sombre légère pour garder le HUD lisible sur fond clair, sans casser la transparence.
    static let glassTint = deepNight.opacity(0.28)
}

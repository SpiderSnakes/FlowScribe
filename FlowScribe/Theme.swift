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
}

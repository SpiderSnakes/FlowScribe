// FlowScribeCore/Sources/FlowScribeCore/Ambiance.swift
import Foundation

public enum AmbiancePalette: String, CaseIterable, Sendable, Codable {
    case nuitBleue, auroreFroide, auroreDuale
}
public enum AmbianceIntensity: String, CaseIterable, Sendable, Codable {
    case discret, equilibre, showcase
}
public enum AmbianceSurface: Sendable { case onboarding, hud, appWindow }

public struct RGBA: Equatable, Sendable {
    public let r, g, b, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    /// hex 0xRRGGBB
    public init(hex: UInt32, a: Double = 1) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255,
                  Double(hex & 0xFF) / 255, a)
    }
}

/// Jeu de rôles FIXE : toute vue peut référencer n'importe quel rôle (cahier §6.1).
public struct PaletteColors: Sendable {
    public let base, baseTop: RGBA
    public let accentPrimary, accentSecondary, accentTertiary, accentQuaternary: RGBA
    public let warm, warmSecondary: RGBA
    public let hairline, textPrimary, textSecondary: RGBA
}

public extension AmbiancePalette {
    var colors: PaletteColors {
        let hairline = RGBA(1, 1, 1, 0.14)
        let textPrimary = RGBA(1, 1, 1, 0.92)
        let textSecondary = RGBA(1, 1, 1, 0.60)
        switch self {
        case .nuitBleue:
            let pr = RGBA(hex: 0x5B8DEF)
            return PaletteColors(base: RGBA(hex: 0x060A1A), baseTop: RGBA(hex: 0x0A1430),
                accentPrimary: pr, accentSecondary: RGBA(hex: 0x7C6CFF),
                accentTertiary: RGBA(hex: 0x3FE0D0), accentQuaternary: pr,
                warm: RGBA(hex: 0xFF8A5C), warmSecondary: RGBA(hex: 0xFF8A5C),
                hairline: hairline, textPrimary: textPrimary, textSecondary: textSecondary)
        case .auroreFroide:
            return PaletteColors(base: RGBA(hex: 0x040712), baseTop: RGBA(hex: 0x091126),
                accentPrimary: RGBA(hex: 0x3A7BFF), accentSecondary: RGBA(hex: 0x9A5CFF),
                accentTertiary: RGBA(hex: 0x2BE7B0), accentQuaternary: RGBA(hex: 0x18C2FF),
                warm: RGBA(hex: 0xFF7A4D), warmSecondary: RGBA(hex: 0xFF7A4D),
                hairline: hairline, textPrimary: textPrimary, textSecondary: textSecondary)
        case .auroreDuale:
            return PaletteColors(base: RGBA(hex: 0x040712), baseTop: RGBA(hex: 0x091126),
                accentPrimary: RGBA(hex: 0x3A7BFF), accentSecondary: RGBA(hex: 0x9A5CFF),
                accentTertiary: RGBA(hex: 0x2BE7B0), accentQuaternary: RGBA(hex: 0x18C2FF),
                warm: RGBA(hex: 0xFF5C8A), warmSecondary: RGBA(hex: 0xFFB23F),
                hairline: hairline, textPrimary: textPrimary, textSecondary: textSecondary)
        }
    }
}

/// Politique d'animation à point unique (cahier §4 + garde-fous).
public func ambianceAnimates(intensity: AmbianceIntensity, surface: AmbianceSurface,
                             reduceMotion: Bool, windowActive: Bool) -> Bool {
    if reduceMotion { return false }
    switch surface {
    case .hud:
        return true                                   // strands du HUD : toujours animés (hors reduce-motion)
    case .onboarding:
        return intensity != .discret
    case .appWindow:
        switch intensity {
        case .discret: return false
        case .equilibre: return windowActive          // pause si fenêtre inactive
        case .showcase: return true
        }
    }
}

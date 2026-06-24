// FlowScribe/BrandPalette.swift
import SwiftUI
import FlowScribeCore

extension RGBA {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

/// Couleurs SwiftUI dérivées d'une palette (les rôles neutres restent neutres ; seuls les accents changent).
struct BrandPalette {
    let colors: PaletteColors
    init(_ p: AmbiancePalette) { colors = p.colors }
    var base: Color { colors.base.color }
    var baseTop: Color { colors.baseTop.color }
    var accentPrimary: Color { colors.accentPrimary.color }
    var accentSecondary: Color { colors.accentSecondary.color }
    var accentTertiary: Color { colors.accentTertiary.color }
    var accentQuaternary: Color { colors.accentQuaternary.color }
    var warm: Color { colors.warm.color }
    var warmSecondary: Color { colors.warmSecondary.color }
    var hairline: Color { colors.hairline.color }
    var auroraColors: [Color] { [accentPrimary, accentSecondary, accentTertiary, accentQuaternary] }
}

/// Valeur injectée dans l'environnement : palette résolue + politique d'animation.
struct Ambiance {
    var palette: BrandPalette
    var intensity: AmbianceIntensity
    func animates(_ surface: AmbianceSurface, reduceMotion: Bool, windowActive: Bool) -> Bool {
        ambianceAnimates(intensity: intensity, surface: surface,
                         reduceMotion: reduceMotion, windowActive: windowActive)
    }
}

private struct AmbianceKey: EnvironmentKey {
    static let defaultValue = Ambiance(palette: BrandPalette(.nuitBleue), intensity: .equilibre)
}
extension EnvironmentValues {
    var ambiance: Ambiance {
        get { self[AmbianceKey.self] }
        set { self[AmbianceKey.self] = newValue }
    }
}

// Libellés FR (l'UI vit dans l'app, pas dans le cœur).
extension AmbiancePalette {
    var title: String {
        switch self {
        case .nuitBleue: return "Nuit bleue"
        case .auroreFroide: return "Aurore froide"
        case .auroreDuale: return "Aurore duale"
        }
    }
}
extension AmbianceIntensity {
    var title: String {
        switch self {
        case .discret: return "Discret"
        case .equilibre: return "Équilibré"
        case .showcase: return "Showcase"
        }
    }
}

import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case accueil, modes, fichiers, corrections, calibration, reglages
    var id: String { rawValue }
    var title: String {
        switch self {
        case .accueil: return "Accueil"
        case .modes: return "Modes"
        case .fichiers: return "Fichiers"
        case .corrections: return "Corrections"
        case .calibration: return "Calibration"
        case .reglages: return "Réglages"
        }
    }
    var icon: String {
        switch self {
        case .accueil: return "house"
        case .modes: return "square.stack.3d.up"
        case .fichiers: return "waveform"
        case .corrections: return "text.book.closed"
        case .calibration: return "mic.badge.plus"
        case .reglages: return "gearshape"
        }
    }
}

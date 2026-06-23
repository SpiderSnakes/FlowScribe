import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case accueil, fichiers, vocabulaire, reglages
    var id: String { rawValue }
    var title: String {
        switch self {
        case .accueil: return "Accueil"
        case .fichiers: return "Fichiers"
        case .vocabulaire: return "Vocabulaire"
        case .reglages: return "Réglages"
        }
    }
    var icon: String {
        switch self {
        case .accueil: return "house"
        case .fichiers: return "waveform"
        case .vocabulaire: return "text.book.closed"
        case .reglages: return "gearshape"
        }
    }
}

import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case accueil, vocabulaire, reglages
    var id: String { rawValue }
    var title: String {
        switch self {
        case .accueil: return "Accueil"
        case .vocabulaire: return "Vocabulaire"
        case .reglages: return "Réglages"
        }
    }
    var icon: String {
        switch self {
        case .accueil: return "house"
        case .vocabulaire: return "text.book.closed"
        case .reglages: return "gearshape"
        }
    }
}

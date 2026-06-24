import Foundation

/// Langues proposées (transcription). `id` = identifiant de locale.
enum AppLocales {
    static let all: [(id: String, name: String)] = [
        ("fr-FR", "Français"),
        ("en-US", "English (US)"),
        ("en-GB", "English (UK)"),
        ("es-ES", "Español"),
        ("de-DE", "Deutsch"),
        ("it-IT", "Italiano"),
        ("pt-PT", "Português"),
        ("nl-NL", "Nederlands"),
    ]

    static func name(for id: String) -> String {
        all.first { $0.id == id }?.name ?? id
    }
}

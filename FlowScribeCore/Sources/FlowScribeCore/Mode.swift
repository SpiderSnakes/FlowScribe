import Foundation

/// Profil par usage : regroupe moteur+modèle, langue, pause musique et style de nettoyage.
public struct Mode: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var provider: EngineProvider
    public var modelId: String
    public var localeIdentifier: String
    public var pauseMusic: Bool
    /// Prompt de reformulation IA propre au mode (nil = pas de nettoyage IA).
    public var cleanupPrompt: String?

    public init(id: UUID = UUID(), name: String, provider: EngineProvider, modelId: String,
                localeIdentifier: String, pauseMusic: Bool, cleanupPrompt: String?) {
        self.id = id; self.name = name; self.provider = provider; self.modelId = modelId
        self.localeIdentifier = localeIdentifier; self.pauseMusic = pauseMusic; self.cleanupPrompt = cleanupPrompt
    }
}

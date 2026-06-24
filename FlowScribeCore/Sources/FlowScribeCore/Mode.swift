import Foundation

/// Reformulation (2ᵉ passe écrite) propre à un mode : un LLM texte reformule la transcription.
public struct Reformulation: Codable, Equatable, Sendable {
    public var provider: EngineProvider   // fournisseur écrit
    public var modelId: String            // modèle écrit
    public var prompt: String
    public init(provider: EngineProvider, modelId: String, prompt: String) {
        self.provider = provider; self.modelId = modelId; self.prompt = prompt
    }
}

/// Profil par usage : transcription (oral) + langue + pause musique + reformulation (écrit) optionnelle.
public struct Mode: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var provider: EngineProvider   // transcription
    public var modelId: String            // modèle de transcription
    public var localeIdentifier: String
    public var pauseMusic: Bool
    /// 2ᵉ passe écrite (nil = transcription brute, pas de reformulation).
    public var reformulation: Reformulation?

    public init(id: UUID = UUID(), name: String, provider: EngineProvider, modelId: String,
                localeIdentifier: String, pauseMusic: Bool, reformulation: Reformulation? = nil) {
        self.id = id; self.name = name; self.provider = provider; self.modelId = modelId
        self.localeIdentifier = localeIdentifier; self.pauseMusic = pauseMusic; self.reformulation = reformulation
    }
}

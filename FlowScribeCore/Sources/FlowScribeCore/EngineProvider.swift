import Foundation

public struct EngineModel: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public init(id: String, displayName: String) { self.id = id; self.displayName = displayName }
}

public enum EngineProvider: String, CaseIterable, Sendable, Codable {
    case appleLocal, elevenLabs, mistral, openAI

    public var displayName: String {
        switch self {
        case .appleLocal: return "Apple (local)"
        case .elevenLabs: return "ElevenLabs Scribe"
        case .mistral: return "Mistral Voxtral"
        case .openAI: return "OpenAI gpt-4o-transcribe"
        }
    }

    /// Clé sous laquelle l'API key est stockée dans le SecretStore (nil pour Apple).
    public var secretKey: String? {
        switch self {
        case .appleLocal: return nil
        case .elevenLabs: return "elevenlabs"
        case .mistral: return "mistral"
        case .openAI: return "openai"
        }
    }

    public var config: CloudEngineConfig? {
        switch self {
        case .appleLocal: return nil
        case .elevenLabs: return .elevenLabs
        case .mistral: return .mistral
        case .openAI: return .openAI
        }
    }

    /// Modèles disponibles par fournisseur (le premier est le défaut).
    public var models: [EngineModel] {
        switch self {
        case .appleLocal:
            return [EngineModel(id: "apple", displayName: "Apple — sur l'appareil")]
        case .elevenLabs:
            return [EngineModel(id: "scribe_v2", displayName: "Scribe v2")]
        case .mistral:
            return [EngineModel(id: "voxtral-mini-latest", displayName: "Voxtral Mini Transcribe")]
        case .openAI:
            return [EngineModel(id: "gpt-4o-transcribe", displayName: "GPT-4o Transcribe"),
                    EngineModel(id: "gpt-4o-mini-transcribe", displayName: "GPT-4o mini Transcribe"),
                    EngineModel(id: "whisper-1", displayName: "Whisper (legacy)")]
        }
    }

    public var defaultModelId: String { models.first?.id ?? "" }

    /// Construit le moteur avec le modèle choisi. Renvoie nil si une clé est requise mais absente.
    public func makeEngine(apiKey: String?, modelId: String? = nil, transport: Transport) -> TranscriptionEngine? {
        if self == .appleLocal { return AppleSpeechEngine() }
        guard let config, let apiKey, !apiKey.isEmpty else { return nil }
        return CloudTranscriptionEngine(config: config, apiKey: apiKey, transport: transport, modelId: modelId ?? defaultModelId)
    }
}

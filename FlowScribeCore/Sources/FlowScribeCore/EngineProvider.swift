import Foundation

public struct EngineModel: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public init(id: String, displayName: String) { self.id = id; self.displayName = displayName }
}

/// Ce qu'un fournisseur sait faire : transcription (oral) et/ou texte (écrit, reformulation/calibration).
public enum Capability: Sendable, Hashable {
    case transcription   // oral
    case text            // écrit (LLM)
}

public enum EngineProvider: String, CaseIterable, Sendable, Codable {
    case appleLocal, elevenLabs, mistral, openAI, anthropic, google

    /// Nom du fournisseur SEUL (le modèle se choisit à part).
    public var displayName: String {
        switch self {
        case .appleLocal: return "Apple (local)"
        case .elevenLabs: return "ElevenLabs"
        case .mistral: return "Mistral"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .google: return "Google"
        }
    }

    /// Clé sous laquelle l'API key est stockée dans le SecretStore (nil pour Apple).
    public var secretKey: String? {
        switch self {
        case .appleLocal: return nil
        case .elevenLabs: return "elevenlabs"
        case .mistral: return "mistral"
        case .openAI: return "openai"
        case .anthropic: return "anthropic"
        case .google: return "google"
        }
    }

    /// Ce que le fournisseur sait faire (oral / écrit).
    public var capabilities: Set<Capability> {
        switch self {
        case .appleLocal: return [.transcription]
        case .elevenLabs: return [.transcription]
        case .mistral, .openAI: return [.transcription, .text]
        case .anthropic, .google: return [.text]
        }
    }

    /// Config du moteur de TRANSCRIPTION (nil si le fournisseur ne fait pas d'oral).
    public var config: CloudEngineConfig? {
        switch self {
        case .appleLocal, .anthropic, .google: return nil
        case .elevenLabs: return .elevenLabs
        case .mistral: return .mistral
        case .openAI: return .openAI
        }
    }

    /// Modèles de transcription (oral) disponibles (le premier est le défaut).
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
        case .anthropic, .google:
            return []   // pas d'oral
        }
    }

    public var defaultModelId: String { models.first?.id ?? "" }

    /// Modèles ÉCRIT (reformulation / calibration) disponibles (le premier est le défaut).
    public var textModels: [EngineModel] {
        switch self {
        case .openAI:
            return [EngineModel(id: "gpt-4o-mini", displayName: "GPT-4o mini"),
                    EngineModel(id: "gpt-4o", displayName: "GPT-4o")]
        case .mistral:
            return [EngineModel(id: "mistral-small-latest", displayName: "Mistral Small"),
                    EngineModel(id: "mistral-large-latest", displayName: "Mistral Large")]
        case .anthropic:
            return [EngineModel(id: "claude-sonnet-4-6", displayName: "Claude Sonnet 4.6"),
                    EngineModel(id: "claude-opus-4-8", displayName: "Claude Opus 4.8")]
        case .google:
            return [EngineModel(id: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash"),
                    EngineModel(id: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro")]
        case .appleLocal, .elevenLabs:
            return []
        }
    }

    public var defaultTextModelId: String { textModels.first?.id ?? "" }

    /// Identifiant de moteur utilisé comme clé des profils de correction (= `id` runtime du moteur).
    public var engineId: String { config?.id ?? "apple.local" }

    /// Fournisseurs capables de transcription (oral) — pour les sélecteurs de moteur.
    public static var transcriptionProviders: [EngineProvider] {
        allCases.filter { $0.capabilities.contains(.transcription) }
    }
    /// Fournisseurs capables de texte (écrit) — pour la reformulation et la calibration IA.
    public static var textProviders: [EngineProvider] {
        allCases.filter { $0.capabilities.contains(.text) }
    }

    /// Construit le moteur de TRANSCRIPTION avec le modèle choisi. Renvoie nil si clé requise absente ou pas d'oral.
    public func makeEngine(apiKey: String?, modelId: String? = nil, transport: Transport) -> TranscriptionEngine? {
        if self == .appleLocal { return AppleSpeechEngine() }
        guard let config, let apiKey, !apiKey.isEmpty else { return nil }
        return CloudTranscriptionEngine(config: config, apiKey: apiKey, transport: transport, modelId: modelId ?? defaultModelId)
    }
}

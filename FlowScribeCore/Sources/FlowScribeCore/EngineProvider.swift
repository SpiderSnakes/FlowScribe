import Foundation

public enum EngineProvider: String, CaseIterable, Sendable {
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

    /// Construit le moteur. Renvoie nil si une clé est requise mais absente.
    public func makeEngine(apiKey: String?, transport: Transport) -> TranscriptionEngine? {
        if self == .appleLocal { return AppleSpeechEngine() }
        guard let config, let apiKey, !apiKey.isEmpty else { return nil }
        return CloudTranscriptionEngine(config: config, apiKey: apiKey, transport: transport)
    }
}

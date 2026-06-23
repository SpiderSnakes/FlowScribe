import Foundation

public struct CloudEngineConfig: Sendable {
    public let id: String
    public let endpoint: URL
    public let authHeaderName: String
    public let authValuePrefix: String
    public let modelField: String
    public let modelValue: String
    public let capabilities: EngineCapabilities
    public let pricePerMinuteUSD: Double

    // IDs/endpoints à confirmer vs docs officielles (cf. Global Constraints du plan M2).
    public static let openAI = CloudEngineConfig(
        id: "openai.gpt-4o-transcribe",
        endpoint: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
        authHeaderName: "Authorization", authValuePrefix: "Bearer ",
        modelField: "model", modelValue: "gpt-4o-transcribe",
        capabilities: EngineCapabilities(supportsStreaming: false, supportsKeyterms: false, isLocal: false),
        pricePerMinuteUSD: 0.006)

    public static let mistral = CloudEngineConfig(
        id: "mistral.voxtral",
        endpoint: URL(string: "https://api.mistral.ai/v1/audio/transcriptions")!,
        authHeaderName: "Authorization", authValuePrefix: "Bearer ",
        modelField: "model", modelValue: "voxtral-mini-latest",
        capabilities: EngineCapabilities(supportsStreaming: false, supportsKeyterms: false, isLocal: false),
        pricePerMinuteUSD: 0.003)

    public static let elevenLabs = CloudEngineConfig(
        id: "elevenlabs.scribe",
        endpoint: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!,
        authHeaderName: "xi-api-key", authValuePrefix: "",
        modelField: "model_id", modelValue: "scribe_v2",
        capabilities: EngineCapabilities(supportsStreaming: false, supportsKeyterms: true, isLocal: false),
        pricePerMinuteUSD: 0.0066)
}

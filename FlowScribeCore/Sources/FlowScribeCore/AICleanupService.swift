import Foundation

public struct CleanupConfig: Sendable {
    public let endpoint: URL
    public let model: String
    public let authHeaderName: String
    public let authValuePrefix: String
    public static let mistral = CleanupConfig(
        endpoint: URL(string: "https://api.mistral.ai/v1/chat/completions")!,
        model: "mistral-small-latest", authHeaderName: "Authorization", authValuePrefix: "Bearer ")
    public static let openAI = CleanupConfig(
        endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
        model: "gpt-4o-mini", authHeaderName: "Authorization", authValuePrefix: "Bearer ")
}

public enum AICleanupError: Error { case httpError(Int), badResponse }

public struct AICleanupService: Sendable {
    private let config: CleanupConfig
    private let apiKey: String
    private let transport: Transport
    public init(config: CleanupConfig, apiKey: String, transport: Transport) {
        self.config = config; self.apiKey = apiKey; self.transport = transport
    }

    public func cleanup(_ text: String) async throws -> String {
        let system = "Corrige la ponctuation et la casse, retire les hésitations (euh, hum) et les répétitions, SANS changer le sens ni la langue. Réponds UNIQUEMENT le texte corrigé."
        let payload: [String: Any] = [
            "model": config.model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": text]
            ],
            "temperature": 0.2
        ]
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("\(config.authValuePrefix)\(apiKey)", forHTTPHeaderField: config.authHeaderName)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw AICleanupError.httpError(response.statusCode) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AICleanupError.badResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

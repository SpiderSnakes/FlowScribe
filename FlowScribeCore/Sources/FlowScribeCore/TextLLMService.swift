import Foundation

public enum TextLLMError: Error { case httpError(Int), badResponse, unsupportedProvider }

/// Appel d'un LLM ÉCRIT (reformulation / calibration). Gère les formats OpenAI & Mistral
/// (chat completions), Anthropic (Messages) et Google Gemini (generateContent).
public struct TextLLMService: Sendable {
    /// Prompt de reformulation par défaut (source unique).
    public static let defaultPrompt = "Corrige la ponctuation et la casse, retire les hésitations (euh, hum) et les répétitions, SANS changer le sens ni la langue. Réponds UNIQUEMENT le texte corrigé."

    private let provider: EngineProvider
    private let model: String
    private let apiKey: String
    private let transport: Transport

    public init(provider: EngineProvider, model: String, apiKey: String, transport: Transport) {
        self.provider = provider; self.model = model; self.apiKey = apiKey; self.transport = transport
    }

    public func complete(system: String, user: String) async throws -> String {
        let request = try buildRequest(system: system, user: user)
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw TextLLMError.httpError(response.statusCode) }
        return try parse(data)
    }

    private func buildRequest(system: String, user: String) throws -> URLRequest {
        switch provider {
        case .openAI, .mistral: return chatRequest(system: system, user: user)
        case .anthropic: return anthropicRequest(system: system, user: user)
        case .google: return geminiRequest(system: system, user: user)
        case .appleLocal, .elevenLabs: throw TextLLMError.unsupportedProvider
        }
    }

    // OpenAI / Mistral — chat completions (format identique)
    private func chatRequest(system: String, user: String) -> URLRequest {
        let endpoint = provider == .openAI
            ? "https://api.openai.com/v1/chat/completions"
            : "https://api.mistral.ai/v1/chat/completions"
        var req = URLRequest(url: URL(string: endpoint)!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
            "temperature": 0.2,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return req
    }

    // Anthropic — Messages API
    private func anthropicRequest(system: String, user: String) -> URLRequest {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "model": model,
            "max_tokens": 1024,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return req
    }

    // Google Gemini — generateContent (clé en query)
    private func geminiRequest(system: String, user: String) -> URLRequest {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": [["text": user]]]],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        return req
    }

    private func parse(_ data: Data) throws -> String {
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw TextLLMError.badResponse }
        let text: String?
        switch provider {
        case .openAI, .mistral:
            let choices = obj["choices"] as? [[String: Any]]
            let msg = choices?.first?["message"] as? [String: Any]
            text = msg?["content"] as? String
        case .anthropic:
            let content = obj["content"] as? [[String: Any]]
            text = content?.first?["text"] as? String
        case .google:
            let candidates = obj["candidates"] as? [[String: Any]]
            let contentObj = candidates?.first?["content"] as? [String: Any]
            let parts = contentObj?["parts"] as? [[String: Any]]
            text = parts?.first?["text"] as? String
        case .appleLocal, .elevenLabs:
            text = nil
        }
        guard let text else { throw TextLLMError.badResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

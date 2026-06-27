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
        let started = Date()
        let request = try buildRequest(system: system, user: user)
        // `host` seulement (pas l'URL complète) : la clé Gemini est passée en query → ne JAMAIS la logger.
        AppLog.info("Reformulation", "envoi \(String(describing: provider)) modèle=\(model) "
                    + "→ \(request.url?.host ?? "?") (\(user.count) car)")
        do {
            let (data, response) = try await transport.send(request)
            let secs = String(format: "%.1fs", Date().timeIntervalSince(started))
            guard (200..<300).contains(response.statusCode) else {
                AppLog.error("Reformulation", "\(String(describing: provider)) HTTP \(response.statusCode) en \(secs)")
                throw TextLLMError.httpError(response.statusCode)
            }
            let text = try parse(data)
            AppLog.info("Reformulation", "\(String(describing: provider)) OK en \(secs) — \(user.count)→\(text.count) car")
            return text
        } catch let e as TextLLMError {
            throw e   // déjà journalisé
        } catch {
            AppLog.error("Reformulation", "\(String(describing: provider)) échec en "
                         + "\(String(format: "%.1fs", Date().timeIntervalSince(started))) : \(error)")
            throw error
        }
    }

    private func buildRequest(system: String, user: String) throws -> URLRequest {
        switch provider {
        case .openAI, .mistral: return try chatRequest(system: system, user: user)
        case .anthropic: return try anthropicRequest(system: system, user: user)
        case .google: return try geminiRequest(system: system, user: user)
        case .appleLocal, .elevenLabs: throw TextLLMError.unsupportedProvider
        }
    }

    // OpenAI / Mistral — chat completions (format identique)
    private func chatRequest(system: String, user: String) throws -> URLRequest {
        let endpoint = provider == .openAI
            ? "https://api.openai.com/v1/chat/completions"
            : "https://api.mistral.ai/v1/chat/completions"
        guard let url = URL(string: endpoint) else { throw TextLLMError.badResponse }
        var req = URLRequest(url: url)
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
    private func anthropicRequest(system: String, user: String) throws -> URLRequest {
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else { throw TextLLMError.badResponse }
        var req = URLRequest(url: url)
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

    // Google Gemini — generateContent (clé en query, encodée proprement via URLComponents)
    private func geminiRequest(system: String, user: String) throws -> URLRequest {
        var comps = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")
        comps?.queryItems = [URLQueryItem(name: "key", value: apiKey)]   // percent-encode la clé
        guard let url = comps?.url else { throw TextLLMError.badResponse }
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

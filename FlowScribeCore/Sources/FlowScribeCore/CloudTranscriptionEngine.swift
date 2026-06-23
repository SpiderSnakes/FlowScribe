import Foundation

public enum CloudTranscriptionError: Error { case httpError(status: Int, body: String), badResponse }

public final class CloudTranscriptionEngine: TranscriptionEngine {
    public var id: String { config.id }
    public var capabilities: EngineCapabilities { config.capabilities }

    private let config: CloudEngineConfig
    private let apiKey: String
    private let transport: Transport
    private let boundary: String

    public init(config: CloudEngineConfig, apiKey: String, transport: Transport, boundary: String = "FlowScribeBoundary") {
        self.config = config; self.apiKey = apiKey; self.transport = transport; self.boundary = boundary
    }

    public func transcribeFile(at url: URL, locale: Locale) async throws -> String {
        let audio = try Data(contentsOf: url)
        var form = MultipartFormData(boundary: boundary)
        form.addField(name: config.modelField, value: config.modelValue)
        form.addFile(name: "file", filename: url.lastPathComponent, contentType: "audio/wav", data: audio)

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("\(config.authValuePrefix)\(apiKey)", forHTTPHeaderField: config.authHeaderName)
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.encoded()

        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw CloudTranscriptionError.httpError(status: response.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["text"] as? String else {
            throw CloudTranscriptionError.badResponse
        }
        return text
    }

    /// Vérifie que la clé est valide via un GET authentifié léger (endpoint de validation).
    public func validateKey() async -> Bool {
        var request = URLRequest(url: config.validationEndpoint)
        request.httpMethod = "GET"
        request.setValue("\(config.authValuePrefix)\(apiKey)", forHTTPHeaderField: config.authHeaderName)
        do {
            let (_, response) = try await transport.send(request)
            return (200..<300).contains(response.statusCode)
        } catch {
            return false
        }
    }
}

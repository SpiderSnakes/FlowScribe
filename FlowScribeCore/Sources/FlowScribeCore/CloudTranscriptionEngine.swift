import Foundation

public enum CloudTranscriptionError: Error { case httpError(status: Int, body: String), badResponse }

/// Résultat détaillé d'un test de clé (statut HTTP + message lisible).
public struct KeyTestResult: Sendable, Equatable {
    public let ok: Bool
    public let status: Int?
    public let message: String?
    public init(ok: Bool, status: Int?, message: String?) {
        self.ok = ok; self.status = status; self.message = message
    }
}

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

    /// Teste la clé sur l'endpoint de transcription lui-même (scope-correct : une clé
    /// limitée au speech-to-text est validée). On distingue l'erreur d'auth de l'erreur de requête.
    public func validateKey() async -> KeyTestResult {
        var form = MultipartFormData(boundary: boundary)
        form.addField(name: config.modelField, value: config.modelValue)

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("\(config.authValuePrefix)\(apiKey)", forHTTPHeaderField: config.authHeaderName)
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.encoded()

        do {
            let (_, response) = try await transport.send(request)
            switch response.statusCode {
            case 401: return KeyTestResult(ok: false, status: 401, message: "Clé invalide")
            case 403: return KeyTestResult(ok: false, status: 403, message: "Permissions insuffisantes pour la transcription")
            case 402: return KeyTestResult(ok: false, status: 402, message: "Quota ou solde insuffisant")
            case 429: return KeyTestResult(ok: false, status: 429, message: "Limite de débit atteinte — réessaie plus tard")
            case 500...599:
                return KeyTestResult(ok: false, status: response.statusCode, message: "Erreur serveur du fournisseur")
            default:
                // 2xx, ou 400/422 (requête incomplète : pas de fichier) = la clé est authentifiée et autorisée.
                return KeyTestResult(ok: true, status: response.statusCode, message: nil)
            }
        } catch {
            return KeyTestResult(ok: false, status: nil, message: error.localizedDescription)
        }
    }
}

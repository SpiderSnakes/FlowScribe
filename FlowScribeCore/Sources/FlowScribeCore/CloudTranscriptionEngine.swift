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
    private let modelId: String?

    public init(config: CloudEngineConfig, apiKey: String, transport: Transport, boundary: String = "FlowScribeBoundary", modelId: String? = nil) {
        self.config = config; self.apiKey = apiKey; self.transport = transport; self.boundary = boundary; self.modelId = modelId
    }

    private var effectiveModel: String { modelId ?? config.modelValue }

    public func transcribeFile(at url: URL, locale: Locale) async throws -> String {
        let started = Date()
        let audio = try Data(contentsOf: url)
        // Type MIME déduit de l'extension réelle : un repli en .caf (si la conversion WAV a échoué) ne doit
        // pas être annoncé comme « audio/wav » — sinon le serveur rejette un en-tête incohérent.
        let contentType = Self.contentType(forExtension: url.pathExtension.lowercased())
        var form = MultipartFormData(boundary: boundary)
        form.addField(name: config.modelField, value: effectiveModel)
        form.addFile(name: "file", filename: url.lastPathComponent, contentType: contentType, data: audio)

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("\(config.authValuePrefix)\(apiKey)", forHTTPHeaderField: config.authHeaderName)
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.encoded()

        // Journalisation diagnostique — JAMAIS la clé ni le texte (uniquement métadonnées et tailles).
        AppLog.info("Cloud", "envoi \(config.id) modèle=\(effectiveModel) → \(config.endpoint.host ?? "?") "
                    + "(\(audio.count / 1024) Ko, \(contentType))")
        do {
            let (data, response) = try await transport.send(request)
            let secs = Self.s(Date().timeIntervalSince(started))
            guard (200..<300).contains(response.statusCode) else {
                let body = String(decoding: data, as: UTF8.self)
                AppLog.error("Cloud", "\(config.id) HTTP \(response.statusCode) en \(secs) — \(Self.snippet(body))")
                throw CloudTranscriptionError.httpError(status: response.statusCode, body: body)
            }
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let text = obj["text"] as? String else {
                AppLog.error("Cloud", "\(config.id) réponse inattendue en \(secs) (\(data.count) o)")
                throw CloudTranscriptionError.badResponse
            }
            AppLog.info("Cloud", "\(config.id) OK HTTP \(response.statusCode) en \(secs) — \(text.count) car")
            return text
        } catch let e as CloudTranscriptionError {
            throw e   // déjà journalisé ci-dessus
        } catch {
            AppLog.error("Cloud", "\(config.id) échec réseau en \(Self.s(Date().timeIntervalSince(started))) : \(error)")
            throw error
        }
    }

    /// Type MIME audio à partir de l'extension de fichier (pour l'upload multipart).
    private static func contentType(forExtension ext: String) -> String {
        switch ext {
        case "wav":          return "audio/wav"
        case "caf":          return "audio/x-caf"
        case "m4a", "mp4":   return "audio/mp4"
        case "mp3":          return "audio/mpeg"
        case "flac":         return "audio/flac"
        case "ogg":          return "audio/ogg"
        default:             return "application/octet-stream"
        }
    }

    private static func s(_ t: TimeInterval) -> String { String(format: "%.1fs", t) }
    /// Tronque un corps de réponse d'erreur pour le log (message d'erreur du fournisseur, jamais de secret).
    private static func snippet(_ s: String) -> String {
        let oneLine = s.replacingOccurrences(of: "\n", with: " ")
        return oneLine.count > 300 ? String(oneLine.prefix(300)) + "…" : oneLine
    }

    /// Teste la clé sur l'endpoint de transcription lui-même (scope-correct : une clé
    /// limitée au speech-to-text est validée). On distingue l'erreur d'auth de l'erreur de requête.
    public func validateKey() async -> KeyTestResult {
        var form = MultipartFormData(boundary: boundary)
        form.addField(name: config.modelField, value: effectiveModel)

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

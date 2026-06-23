import Foundation

public protocol TranscriptionEngine: Sendable {
    var id: String { get }
    var capabilities: EngineCapabilities { get }
    /// Transcrit un fichier audio déjà enregistré sur disque.
    func transcribeFile(at url: URL, locale: Locale) async throws -> String
}

/// Moteur factice pour les tests : renvoie un texte fixe.
public final class MockEngine: TranscriptionEngine {
    public let id: String
    public let capabilities: EngineCapabilities
    private let result: String
    public init(id: String, result: String) {
        self.id = id
        self.result = result
        self.capabilities = EngineCapabilities(supportsStreaming: false, supportsKeyterms: false, isLocal: true)
    }
    public func transcribeFile(at url: URL, locale: Locale) async throws -> String {
        result
    }
}

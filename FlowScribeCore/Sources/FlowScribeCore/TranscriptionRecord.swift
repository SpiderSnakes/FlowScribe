import Foundation

public struct TranscriptionRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let text: String
    public let engineId: String
    public let locale: String
    public let audioFileName: String
    public let duration: TimeInterval?
    /// Échec récupérable : message court (l'audio est conservé pour relancer). `nil` = succès.
    /// Optionnel → l'ancien `history.json` (sans la clé) se décode comme un succès.
    public let errorMessage: String?

    public init(id: UUID, date: Date, text: String, engineId: String, locale: String,
                audioFileName: String, duration: TimeInterval?, errorMessage: String? = nil) {
        self.id = id; self.date = date; self.text = text; self.engineId = engineId
        self.locale = locale; self.audioFileName = audioFileName; self.duration = duration
        self.errorMessage = errorMessage
    }

    /// `true` si la transcription a échoué (audio conservé, relance possible).
    public var failed: Bool { errorMessage != nil }
}

import Foundation

public struct TranscriptionRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let text: String
    public let engineId: String
    public let locale: String
    public let audioFileName: String
    public let duration: TimeInterval?
    public init(id: UUID, date: Date, text: String, engineId: String, locale: String, audioFileName: String, duration: TimeInterval?) {
        self.id = id; self.date = date; self.text = text; self.engineId = engineId
        self.locale = locale; self.audioFileName = audioFileName; self.duration = duration
    }
}

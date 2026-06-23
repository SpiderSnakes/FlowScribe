import Foundation

public enum TranscriptionOutcome: Equatable, Sendable {
    case success(text: String, engineId: String, usedFallback: Bool)
    case failed
}

public final class TranscriptionService: Sendable {
    private let primary: TranscriptionEngine
    private let fallback: TranscriptionEngine
    public init(primary: TranscriptionEngine, fallback: TranscriptionEngine) {
        self.primary = primary
        self.fallback = fallback
    }

    public func transcribe(fileAt url: URL, locale: Locale) async -> TranscriptionOutcome {
        do {
            let text = try await primary.transcribeFile(at: url, locale: locale)
            return .success(text: text, engineId: primary.id, usedFallback: false)
        } catch {
            // Repli : on ne perd jamais l'audio, on retente en local sur le fichier sauvegardé.
            do {
                let text = try await fallback.transcribeFile(at: url, locale: locale)
                return .success(text: text, engineId: fallback.id, usedFallback: true)
            } catch {
                return .failed
            }
        }
    }
}

import Foundation

public enum TranscriptionOutcome: Equatable, Sendable {
    case success(text: String, engineId: String, usedFallback: Bool)
    case failed
}

public final class TranscriptionService: Sendable {
    private let primary: TranscriptionEngine
    private let fallback: TranscriptionEngine
    private let timeoutSeconds: Double

    public init(primary: TranscriptionEngine, fallback: TranscriptionEngine, timeoutSeconds: Double = 30) {
        self.primary = primary
        self.fallback = fallback
        self.timeoutSeconds = timeoutSeconds
    }

    public func transcribe(fileAt url: URL, locale: Locale) async -> TranscriptionOutcome {
        if let text = await tryEngine(primary, url: url, locale: locale) {
            return .success(text: text, engineId: primary.id, usedFallback: false)
        }
        // Repli (sauf si le repli est le même moteur que le primaire — évite de doubler le timeout).
        if primary.id != fallback.id, let text = await tryEngine(fallback, url: url, locale: locale) {
            return .success(text: text, engineId: fallback.id, usedFallback: true)
        }
        return .failed
    }

    /// Tente un moteur avec timeout ; renvoie nil si erreur ou délai dépassé.
    private func tryEngine(_ engine: TranscriptionEngine, url: URL, locale: Locale) async -> String? {
        do {
            return try await withTimeout(seconds: timeoutSeconds) {
                try await engine.transcribeFile(at: url, locale: locale)
            }
        } catch {
            return nil
        }
    }
}

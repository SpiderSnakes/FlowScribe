import Foundation

public enum TranscriptionOutcome: Equatable, Sendable {
    case success(text: String, engineId: String, usedFallback: Bool)
    case failed
}

public final class TranscriptionService: Sendable {
    private let primary: TranscriptionEngine
    private let fallback: TranscriptionEngine
    private let timeoutSeconds: Double
    private let postCorrector: PostCorrector?

    public init(primary: TranscriptionEngine, fallback: TranscriptionEngine, timeoutSeconds: Double = 30, postCorrector: PostCorrector? = nil) {
        self.primary = primary
        self.fallback = fallback
        self.timeoutSeconds = timeoutSeconds
        self.postCorrector = postCorrector
    }

    public func transcribe(fileAt url: URL, locale: Locale, audioDuration: TimeInterval? = nil) async -> TranscriptionOutcome {
        let timeout = effectiveTimeout(for: audioDuration)
        if let text = await tryEngine(primary, url: url, locale: locale, timeout: timeout) {
            return .success(text: corrected(text, primary.id), engineId: primary.id, usedFallback: false)
        }
        // Repli (sauf si le repli est le même moteur que le primaire — évite de doubler le timeout).
        if primary.id != fallback.id, let text = await tryEngine(fallback, url: url, locale: locale, timeout: timeout) {
            return .success(text: corrected(text, fallback.id), engineId: fallback.id, usedFallback: true)
        }
        AppLog.error("Transcription", "échec final (tous les moteurs) sur \(url.lastPathComponent)")
        return .failed
    }

    /// Le moteur on-device peut être plus lent que le temps réel sur les longues dictées :
    /// on étire le délai en fonction de la durée audio (plancher = `timeoutSeconds`).
    func effectiveTimeout(for duration: TimeInterval?) -> Double {
        guard let d = duration, d > 0 else { return timeoutSeconds }
        return max(timeoutSeconds, d * 2 + 20)
    }

    /// Applique la post-correction propre au moteur qui a produit le texte.
    private func corrected(_ text: String, _ engineId: String) -> String {
        postCorrector?.correct(text, engineId: engineId) ?? text
    }

    /// Tente un moteur avec timeout ; renvoie nil si erreur ou délai dépassé (journalisé).
    private func tryEngine(_ engine: TranscriptionEngine, url: URL, locale: Locale, timeout: Double) async -> String? {
        let started = Date()
        do {
            let text = try await withTimeout(seconds: timeout) {
                try await engine.transcribeFile(at: url, locale: locale)
            }
            AppLog.info("Transcription", "\(engine.id) OK en \(Self.s(Date().timeIntervalSince(started)))")
            return text
        } catch is TimeoutError {
            AppLog.error("Transcription", "\(engine.id) délai dépassé (\(Int(timeout))s) sur \(url.lastPathComponent)")
            return nil
        } catch {
            AppLog.error("Transcription", "\(engine.id) erreur : \(error)")
            return nil
        }
    }

    private static func s(_ t: TimeInterval) -> String { String(format: "%.1fs", t) }
}

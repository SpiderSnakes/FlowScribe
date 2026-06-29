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
        // Timeout calculé PAR moteur : l'étirement basé sur la durée ne vaut que pour les moteurs locaux
        // (cf. effectiveTimeout) ; un moteur cloud bloqué doit basculer vers le repli sous un délai borné.
        let primaryTimeout = effectiveTimeout(for: audioDuration, engine: primary)
        let fallbackTimeout = effectiveTimeout(for: audioDuration, engine: fallback)
        AppLog.info("Transcription", "début \(url.lastPathComponent) — primaire=\(primary.id) repli=\(fallback.id) "
                    + "locale=\(locale.identifier) timeout=\(Int(primaryTimeout))s/\(Int(fallbackTimeout))s")
        if let text = await tryEngine(primary, url: url, locale: locale, timeout: primaryTimeout) {
            return .success(text: corrected(text, primary.id), engineId: primary.id, usedFallback: false)
        }
        // Repli (sauf si le repli est le même moteur que le primaire — évite de doubler le timeout).
        if primary.id != fallback.id, let text = await tryEngine(fallback, url: url, locale: locale, timeout: fallbackTimeout) {
            return .success(text: corrected(text, fallback.id), engineId: fallback.id, usedFallback: true)
        }
        AppLog.error("Transcription", "échec final (tous les moteurs) sur \(url.lastPathComponent)")
        return .failed
    }

    /// Délai propre au moteur. Le moteur on-device peut être plus lent que le temps réel sur les longues
    /// dictées : on étire alors le délai en fonction de la durée audio (plancher = `timeoutSeconds`).
    /// Pour un moteur cloud (réseau), on garde un plafond borné : un upload bloqué doit basculer vite
    /// vers le repli local plutôt que d'attendre plusieurs minutes.
    func effectiveTimeout(for duration: TimeInterval?, engine: TranscriptionEngine) -> Double {
        guard let d = duration, d > 0 else { return timeoutSeconds }
        if engine.capabilities.isLocal {
            return max(timeoutSeconds, d * 2 + 20)
        }
        return max(timeoutSeconds, min(d + 30, 90))
    }

    /// Surcharge de compatibilité : applique le calcul du moteur primaire (rétro-compatible).
    func effectiveTimeout(for duration: TimeInterval?) -> Double {
        effectiveTimeout(for: duration, engine: primary)
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

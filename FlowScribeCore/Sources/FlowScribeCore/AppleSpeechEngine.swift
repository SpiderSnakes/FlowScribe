import Foundation
import Speech
import AVFoundation
import Synchronization

public enum AppleSpeechError: Error {
    case unavailable
    case localeUnsupported
    case assetDownloadInProgress
}

public final class AppleSpeechEngine: TranscriptionEngine {
    public let id = "apple.local"
    public let capabilities = EngineCapabilities(supportsStreaming: true, supportsKeyterms: false, isLocal: true)

    /// État de disponibilité du modèle on-device, mis à jour par `prepareModel`. OPTIMISTE par défaut
    /// (`true`) : tant qu'on n'a pas constaté l'inverse, on n'empêche JAMAIS d'enregistrer. Sert au
    /// garde-fou pré-enregistrement (ne pas lancer une dictée Apple vouée à échouer).
    private static let readyFlag = Atomic<Bool>(true)
    /// `true` si le dernier `prepareModel` a confirmé le modèle prêt (ou si on n'a pas encore vérifié).
    public static var isModelReady: Bool { readyFlag.load(ordering: .relaxed) }

    public init() {}

    public func transcribeFile(at url: URL, locale: Locale) async throws -> String {
        let started = Date()
        do {
            let transcriber = try await Self.makeReadyTranscriber(locale: locale)
            let audioFile = try AVAudioFile(forReading: url)
            let fmt = audioFile.processingFormat
            let secs = Double(audioFile.length) / max(1, fmt.sampleRate)
            AppLog.info("AppleSpeech", "lecture \(url.lastPathComponent) — \(Int(fmt.sampleRate))Hz \(fmt.channelCount)ch ~\(String(format: "%.1f", secs))s")

            async let collected: AttributedString = transcriber.results.reduce(into: AttributedString()) { acc, result in
                acc += result.text
            }

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            let text = String(try await collected.characters)
            AppLog.info("AppleSpeech", "OK — \(text.count) car en \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
            return text
        } catch {
            // L'erreur réelle (souvent invisible jusqu'ici) est capturée dans le fichier de log.
            AppLog.error("AppleSpeech", "échec après \(String(format: "%.1f", Date().timeIntervalSince(started)))s : \(error)")
            throw error
        }
    }

    /// Pré-télécharge le modèle de la locale au lancement (best-effort, en tâche de fond) pour qu'il
    /// soit prêt quand l'utilisateur dicte — le téléchargement on-device peut prendre du temps.
    @discardableResult
    public static func prepareModel(locale: Locale) async -> Bool {
        do {
            _ = try await makeReadyTranscriber(locale: locale)
            readyFlag.store(true, ordering: .relaxed)
            AppLog.info("AppleSpeech", "modèle prêt (\(locale.identifier))")
            return true
        } catch {
            readyFlag.store(false, ordering: .relaxed)
            AppLog.warn("AppleSpeech", "préchargement du modèle (\(locale.identifier)) : \(error)")
            return false
        }
    }

    /// Vérifie la disponibilité et installe le modèle de langue si nécessaire (avec journalisation détaillée).
    private static func makeReadyTranscriber(locale: Locale) async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else { throw AppleSpeechError.unavailable }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw AppleSpeechError.localeUnsupported
        }
        let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)

        // SOURCE DE VÉRITÉ : `installedLocales`. ⚠️ `AssetInventory.status(forModules:)` renvoie
        // « .supported » même quand la locale EST installée et fonctionnelle (faux négatif confirmé sur
        // l'appareil : status=.supported alors que la transcription marche). Ne JAMAIS gater la
        // disponibilité sur `status` — sinon on rejette un modèle pourtant prêt (bug « assetDownloadInProgress »).
        if await isInstalled(supported) {
            await reserveIfNeeded(supported)
            return transcriber
        }

        AppLog.info("AppleSpeech", "modèle \(supported.identifier) non installé — téléchargement…")
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        } else {
            AppLog.warn("AppleSpeech", "aucune requête d'installation pour \(supported.identifier) (rien à télécharger ou indisponible)")
        }
        guard await isInstalled(supported) else {
            AppLog.error("AppleSpeech", "modèle \(supported.identifier) toujours indisponible après tentative de téléchargement")
            throw AppleSpeechError.assetDownloadInProgress
        }
        await reserveIfNeeded(supported)
        return transcriber
    }

    /// `true` si la locale figure dans les modèles RÉELLEMENT installés (comparaison BCP-47).
    private static func isInstalled(_ locale: Locale) async -> Bool {
        let target = locale.identifier(.bcp47)
        return await SpeechTranscriber.installedLocales.contains { $0.identifier(.bcp47) == target }
    }

    /// Réserve la locale (best-effort) pour empêcher macOS de purger le modèle entre les sessions —
    /// ce qui expliquait l'oscillation « marche puis ne marche plus » d'une session à l'autre.
    private static func reserveIfNeeded(_ locale: Locale) async {
        let target = locale.identifier(.bcp47)
        if await AssetInventory.reservedLocales.contains(where: { $0.identifier(.bcp47) == target }) { return }
        do {
            try await AssetInventory.reserve(locale: locale)
            AppLog.info("AppleSpeech", "locale \(target) réservée (anti-éviction)")
        } catch {
            AppLog.warn("AppleSpeech", "réservation de \(target) impossible : \(error)")
        }
    }
}

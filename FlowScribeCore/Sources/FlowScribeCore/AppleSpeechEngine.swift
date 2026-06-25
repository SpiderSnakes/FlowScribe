import Foundation
import Speech
import AVFoundation

public enum AppleSpeechError: Error {
    case unavailable
    case localeUnsupported
    case assetDownloadInProgress
}

public final class AppleSpeechEngine: TranscriptionEngine {
    public let id = "apple.local"
    public let capabilities = EngineCapabilities(supportsStreaming: true, supportsKeyterms: false, isLocal: true)

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

    /// Vérifie la disponibilité et installe le modèle de langue si nécessaire.
    private static func makeReadyTranscriber(locale: Locale) async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else { throw AppleSpeechError.unavailable }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw AppleSpeechError.localeUnsupported
        }
        let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            return transcriber
        default:
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
                throw AppleSpeechError.assetDownloadInProgress
            }
            return transcriber
        }
    }
}

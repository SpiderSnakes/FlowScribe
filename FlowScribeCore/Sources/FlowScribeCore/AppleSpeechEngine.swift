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
        let transcriber = try await Self.makeReadyTranscriber(locale: locale)

        async let collected: AttributedString = transcriber.results.reduce(into: AttributedString()) { acc, result in
            acc += result.text
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: url)
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        let attributed = try await collected
        return String(attributed.characters)
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

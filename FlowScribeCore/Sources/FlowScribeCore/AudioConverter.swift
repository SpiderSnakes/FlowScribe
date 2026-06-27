import Foundation
import AVFoundation

/// Conversion audio → WAV. On enregistre en CAF (robuste à une interruption/crash : conteneur en flux),
/// puis on convertit en WAV (PCM 16 bits) accepté par TOUS les fournisseurs (OpenAI/Mistral rejettent le CAF).
/// La conversion vérifie que le WAV produit est lisible AVANT de (le cas échéant) supprimer la source —
/// donc jamais de perte : si la conversion échoue, la source est conservée.
public enum AudioConverter {
    /// Convertit `source` en WAV à côté (même nom de base, extension `.wav`).
    /// - Returns: l'URL du WAV vérifié, ou `nil` si la conversion/vérification échoue (source intacte).
    @discardableResult
    public static func convertToWAV(_ source: URL, deleteSourceOnSuccess: Bool) -> URL? {
        if source.pathExtension.lowercased() == "wav" { return source }   // déjà au bon format
        let dest = source.deletingPathExtension().appendingPathExtension("wav")
        do {
            let input = try AVAudioFile(forReading: source)
            let processing = input.processingFormat
            let frames = input.length
            guard frames > 0 else {
                AppLog.warn("AudioConverter", "source vide \(source.lastPathComponent)")
                return nil
            }
            // WAV PCM 16 bits, même taux d'échantillonnage / canaux — universellement accepté.
            let wavSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: processing.sampleRate,
                AVNumberOfChannelsKey: processing.channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
            ]
            if FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.removeItem(at: dest) }
            guard let buffer = AVAudioPCMBuffer(pcmFormat: processing, frameCapacity: 16384) else {
                AppLog.error("AudioConverter", "buffer impossible pour \(source.lastPathComponent)")
                return nil
            }
            // Scope interne : `output` est libéré ici → l'en-tête WAV est flushé AVANT la vérification.
            do {
                let output = try AVAudioFile(forWriting: dest, settings: wavSettings)
                while input.framePosition < frames {
                    try input.read(into: buffer)
                    if buffer.frameLength == 0 { break }
                    try output.write(from: buffer)
                }
            }
            // Vérifie que le WAV est réellement lisible et non vide.
            let check = try AVAudioFile(forReading: dest)
            guard check.length > 0 else {
                AppLog.error("AudioConverter", "WAV produit vide/invalide pour \(source.lastPathComponent)")
                try? FileManager.default.removeItem(at: dest)
                return nil
            }
            if deleteSourceOnSuccess { try? FileManager.default.removeItem(at: source) }
            AppLog.info("AudioConverter", "\(source.lastPathComponent) → \(dest.lastPathComponent) (\(check.length) frames)")
            return dest
        } catch {
            AppLog.error("AudioConverter", "échec conversion \(source.lastPathComponent) : \(error)")
            try? FileManager.default.removeItem(at: dest)   // nettoie un WAV partiel éventuel
            return nil
        }
    }

    /// Durée (s) d'un fichier audio lisible, ou `nil`.
    public static func duration(of url: URL) -> TimeInterval? {
        guard let f = try? AVAudioFile(forReading: url), f.processingFormat.sampleRate > 0 else { return nil }
        return Double(f.length) / f.processingFormat.sampleRate
    }
}

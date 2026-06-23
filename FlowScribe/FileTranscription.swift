import Foundation
import AVFoundation

/// Utilitaires pour la transcription de fichiers importés.
enum FileTranscription {
    /// Durée best-effort d'un fichier audio (nil si indéterminable).
    static func duration(of url: URL) async -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard let cm = try? await asset.load(.duration) else { return nil }
        let secs = CMTimeGetSeconds(cm)
        return secs.isFinite && secs > 0 ? secs : nil
    }
}

import SwiftUI
import AVFoundation

/// Lecture simple d'un enregistrement (le `.caf` d'une transcription).
@MainActor
@Observable
final class AudioPlayback {
    var isPlaying = false
    private var player: AVAudioPlayer?

    func toggle(url: URL) {
        if isPlaying { stop(); return }
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        player = p
        p.play()
        isPlaying = true
        // Réinitialise l'état quand la lecture se termine (sans délégué).
        Task { @MainActor in
            while p.isPlaying { try? await Task.sleep(for: .milliseconds(300)) }
            if player === p { isPlaying = false; player = nil }
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }
}

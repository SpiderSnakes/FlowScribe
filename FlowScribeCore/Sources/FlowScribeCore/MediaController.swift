import Foundation

public enum MediaSource: String, CaseIterable, Sendable, Equatable { case music, spotify }

public protocol MediaPlayer: Sendable {
    func isPlaying(_ source: MediaSource) -> Bool
    func pause(_ source: MediaSource)
    func play(_ source: MediaSource)
}

@MainActor
public final class MediaController {
    private let player: MediaPlayer
    private let enabled: Bool
    private var paused: [MediaSource] = []

    public init(player: MediaPlayer, enabled: Bool) {
        self.player = player
        self.enabled = enabled
    }

    /// Met en pause ce qui joue, et mémorise pour ne relancer que ça.
    public func pauseForDictation() {
        guard enabled else { return }
        paused = []
        for s in MediaSource.allCases where player.isPlaying(s) {
            player.pause(s)
            paused.append(s)
        }
    }

    /// Relance exactement ce qu'on a mis en pause.
    public func resumeAfterDictation() {
        for s in paused { player.play(s) }
        paused = []
    }
}

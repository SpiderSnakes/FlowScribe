import XCTest
@testable import FlowScribeCore

@MainActor
final class MediaControllerTests: XCTestCase {
    final class SpyPlayer: MediaPlayer {
        nonisolated(unsafe) var playing: Set<MediaSource>
        nonisolated(unsafe) var paused: [MediaSource] = []
        nonisolated(unsafe) var resumed: [MediaSource] = []
        init(playing: Set<MediaSource>) { self.playing = playing }
        func isPlaying(_ s: MediaSource) -> Bool { playing.contains(s) }
        func pause(_ s: MediaSource) { paused.append(s); playing.remove(s) }
        func play(_ s: MediaSource) { resumed.append(s); playing.insert(s) }
    }

    func test_pausesOnlyPlaying_resumesOnlyPaused() {
        let player = SpyPlayer(playing: [.spotify])
        let c = MediaController(player: player, enabled: true)
        c.pauseForDictation()
        XCTAssertEqual(player.paused, [.spotify])
        c.resumeAfterDictation()
        XCTAssertEqual(player.resumed, [.spotify])
    }

    func test_disabled_doesNothing() {
        let player = SpyPlayer(playing: [.music])
        let c = MediaController(player: player, enabled: false)
        c.pauseForDictation(); c.resumeAfterDictation()
        XCTAssertTrue(player.paused.isEmpty); XCTAssertTrue(player.resumed.isEmpty)
    }

    func test_nothingPlaying_resumesNothing() {
        let player = SpyPlayer(playing: [])
        let c = MediaController(player: player, enabled: true)
        c.pauseForDictation(); c.resumeAfterDictation()
        XCTAssertTrue(player.resumed.isEmpty)
    }
}

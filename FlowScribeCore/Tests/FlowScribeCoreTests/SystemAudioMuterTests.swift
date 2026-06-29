import XCTest
@testable import FlowScribeCore

/// Sortie factice : simule un périphérique avec mute OU volume (selon ce qu'on lui dit de supporter).
private final class FakeOutput: SystemOutputControlling, @unchecked Sendable {
    var mute: Bool?
    var volume: Float?
    func currentMute() -> Bool? { mute }
    func setMute(_ m: Bool) { mute = m }
    func currentVolume() -> Float? { volume }
    func setVolume(_ v: Float) { volume = v }
}

@MainActor
final class SystemAudioMuterTests: XCTestCase {
    func test_mute_thenRestore_returnsToUnmuted() {
        let out = FakeOutput(); out.mute = false
        let m = SystemAudioMuter(output: out, enabled: true)
        m.muteForDictation()
        XCTAssertEqual(out.mute, true, "doit couper le son")
        m.restoreAfterDictation()
        XCTAssertEqual(out.mute, false, "doit rétablir l'état précédent (non muet)")
    }

    func test_restore_keepsMuted_ifAlreadyMutedBefore() {
        let out = FakeOutput(); out.mute = true   // déjà muet avant la dictée
        let m = SystemAudioMuter(output: out, enabled: true)
        m.muteForDictation()
        XCTAssertEqual(out.mute, true)
        m.restoreAfterDictation()
        XCTAssertEqual(out.mute, true, "ne doit PAS réactiver le son si l'utilisateur l'avait déjà coupé")
    }

    func test_volumeFallback_whenNoMuteControl() {
        let out = FakeOutput(); out.mute = nil; out.volume = 0.6   // pas de mute → repli volume
        let m = SystemAudioMuter(output: out, enabled: true)
        m.muteForDictation()
        XCTAssertEqual(out.volume, 0, "doit mettre le volume à 0")
        m.restoreAfterDictation()
        XCTAssertEqual(out.volume, 0.6, "doit restaurer le volume exact")
    }

    func test_disabled_doesNothing() {
        let out = FakeOutput(); out.mute = false
        let m = SystemAudioMuter(output: out, enabled: false)
        m.muteForDictation()
        XCTAssertEqual(out.mute, false, "désactivé → ne touche à rien")
    }

    func test_mute_isIdempotent_beforeRestore() {
        let out = FakeOutput(); out.mute = false
        let m = SystemAudioMuter(output: out, enabled: true)
        m.muteForDictation()
        out.mute = false                 // simulate l'utilisateur réactive le son manuellement
        m.muteForDictation()             // 2e appel sans restore → ne réécrase pas l'état mémorisé
        m.restoreAfterDictation()
        XCTAssertEqual(out.mute, false, "restaure l'état mémorisé au 1er mute (non muet)")
    }
}

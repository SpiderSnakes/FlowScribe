import XCTest
@testable import FlowScribeCore

@MainActor
final class DictationControllerTests: XCTestCase {

    final class SpyRecorder: AudioRecorder {
        nonisolated(unsafe) var startCount = 0
        nonisolated(unsafe) var stopCount = 0
        func start() throws { startCount += 1 }
        func stop() async -> AudioRecording { stopCount += 1; return AudioRecording(url: URL(filePath: "/tmp/a.caf"), duration: 1) }
    }
    final class SpyOutput: TextOutput {
        nonisolated(unsafe) var delivered: [String] = []
        func deliver(_ text: String) { delivered.append(text) }
    }

    func makeController() -> (DictationController, SpyRecorder, SpyOutput) {
        let rec = SpyRecorder(); let out = SpyOutput()
        let service = TranscriptionService(primary: MockEngine(id: "mock", result: "salut"),
                                           fallback: MockEngine(id: "apple", result: "local"))
        let c = DictationController(recorder: rec, service: service, output: out, locale: Locale(identifier: "fr-FR"))
        return (c, rec, out)
    }

    func test_tap_startsThenStops_andDelivers() async {
        let (c, rec, out) = makeController()
        // 1er tap : démarre
        c.pressDown(); await c.pressUp(kind: .tap)
        XCTAssertEqual(c.state, .recording)
        XCTAssertEqual(rec.startCount, 1)
        // 2e tap : arrête + transcrit + livre
        c.pressDown(); await c.pressUp(kind: .tap)
        XCTAssertEqual(rec.stopCount, 1)
        XCTAssertEqual(out.delivered, ["salut"])
        XCTAssertEqual(c.state, .idle)
    }

    func test_hold_recordsWhileHeld_thenStopsOnRelease() async {
        let (c, rec, out) = makeController()
        c.pressDown()                      // keyDown : démarre
        XCTAssertEqual(rec.startCount, 1)
        XCTAssertEqual(c.state, .recording)
        await c.pressUp(kind: .hold)        // keyUp long : arrête + livre
        XCTAssertEqual(rec.stopCount, 1)
        XCTAssertEqual(out.delivered, ["salut"])
        XCTAssertEqual(c.state, .idle)
    }

    func test_onFinish_receivesOutcome() async {
        let (c, _, _) = makeController()
        var received: TranscriptionOutcome?
        c.onFinish = { received = $0 }
        c.pressDown(); await c.pressUp(kind: .hold)
        XCTAssertEqual(received, .success(text: "salut", engineId: "mock", usedFallback: false))
    }

    func test_configure_swapsEngineAtRuntime() async {
        let (c, _, out) = makeController()
        c.configure(service: TranscriptionService(primary: MockEngine(id: "e2", result: "nouveau"),
                                                   fallback: MockEngine(id: "a", result: "l")),
                    locale: Locale(identifier: "en-US"))
        c.pressDown(); await c.pressUp(kind: .hold)
        XCTAssertEqual(out.delivered, ["nouveau"])
    }
}

import XCTest
@testable import FlowScribeCore

final class TranscriptionServiceTests: XCTestCase {
    struct ThrowingEngine: TranscriptionEngine {
        let id: String
        let capabilities = EngineCapabilities(supportsStreaming: false, supportsKeyterms: false, isLocal: false)
        func transcribeFile(at url: URL, locale: Locale) async throws -> String { throw URLError(.notConnectedToInternet) }
    }
    struct HangingEngine: TranscriptionEngine {
        let id: String
        let capabilities = EngineCapabilities(supportsStreaming: false, supportsKeyterms: false, isLocal: false)
        func transcribeFile(at url: URL, locale: Locale) async throws -> String {
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return "jamais"
        }
    }

    func test_usesPrimary_whenItSucceeds() async {
        let service = TranscriptionService(primary: MockEngine(id: "p", result: "primaire"),
                                           fallback: MockEngine(id: "apple", result: "local"))
        let out = await service.transcribe(fileAt: URL(filePath: "/tmp/x.caf"), locale: .current)
        XCTAssertEqual(out, .success(text: "primaire", engineId: "p", usedFallback: false))
    }

    func test_fallsBackToApple_whenPrimaryThrows() async {
        let service = TranscriptionService(primary: ThrowingEngine(id: "boom"),
                                           fallback: MockEngine(id: "apple", result: "local"))
        let out = await service.transcribe(fileAt: URL(filePath: "/tmp/x.caf"), locale: .current)
        XCTAssertEqual(out, .success(text: "local", engineId: "apple", usedFallback: true))
    }

    func test_timesOut_thenFallsBack() async {
        let service = TranscriptionService(primary: HangingEngine(id: "hang"),
                                           fallback: MockEngine(id: "apple", result: "local"),
                                           timeoutSeconds: 0.2)
        let out = await service.transcribe(fileAt: URL(filePath: "/tmp/x.caf"), locale: .current)
        XCTAssertEqual(out, .success(text: "local", engineId: "apple", usedFallback: true))
    }

    func test_bothFail_returnsFailed() async {
        let service = TranscriptionService(primary: HangingEngine(id: "hang1"),
                                           fallback: ThrowingEngine(id: "boom2"),
                                           timeoutSeconds: 0.2)
        let out = await service.transcribe(fileAt: URL(filePath: "/tmp/x.caf"), locale: .current)
        XCTAssertEqual(out, .failed)
    }
}

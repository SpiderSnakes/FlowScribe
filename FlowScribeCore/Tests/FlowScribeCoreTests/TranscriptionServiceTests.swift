import XCTest
@testable import FlowScribeCore

final class TranscriptionServiceTests: XCTestCase {
    struct ThrowingEngine: TranscriptionEngine {
        let id = "boom"
        let capabilities = EngineCapabilities(supportsStreaming: false, supportsKeyterms: false, isLocal: false)
        func transcribeFile(at url: URL, locale: Locale) async throws -> String { throw URLError(.notConnectedToInternet) }
    }

    func test_usesPrimary_whenItSucceeds() async {
        let service = TranscriptionService(primary: MockEngine(id: "p", result: "primaire"),
                                           fallback: MockEngine(id: "apple", result: "local"))
        let out = await service.transcribe(fileAt: URL(filePath: "/tmp/x.caf"), locale: .current)
        XCTAssertEqual(out, .success(text: "primaire", engineId: "p", usedFallback: false))
    }

    func test_fallsBackToApple_whenPrimaryThrows() async {
        let service = TranscriptionService(primary: ThrowingEngine(),
                                           fallback: MockEngine(id: "apple", result: "local"))
        let out = await service.transcribe(fileAt: URL(filePath: "/tmp/x.caf"), locale: .current)
        XCTAssertEqual(out, .success(text: "local", engineId: "apple", usedFallback: true))
    }
}

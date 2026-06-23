import XCTest
@testable import FlowScribeCore

final class TranscriptionEngineTests: XCTestCase {
    func test_mockEngine_returnsConfiguredText() async throws {
        let engine = MockEngine(id: "mock", result: "bonjour le monde")
        let text = try await engine.transcribeFile(at: URL(filePath: "/tmp/x.caf"), locale: Locale(identifier: "fr-FR"))
        XCTAssertEqual(text, "bonjour le monde")
        XCTAssertTrue(engine.capabilities.isLocal)
    }
}

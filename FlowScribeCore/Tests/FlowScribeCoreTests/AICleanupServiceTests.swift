import XCTest
@testable import FlowScribeCore

final class AICleanupServiceTests: XCTestCase {
    func test_cleanup_postsChat_andParsesContent() async throws {
        let body = #"{"choices":[{"message":{"content":"Bonjour, ceci est propre."}}]}"#
        let mock = MockTransport(statusCode: 200, body: Data(body.utf8))
        let svc = AICleanupService(config: .mistral, apiKey: "k", transport: mock)
        let out = try await svc.cleanup("euh bonjour ceci est euh propre")
        XCTAssertEqual(out, "Bonjour, ceci est propre.")
        let req = mock.lastRequest
        XCTAssertEqual(req?.httpMethod, "POST")
        XCTAssertEqual(req?.url, CleanupConfig.mistral.endpoint)
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Authorization"), "Bearer k")
    }
    func test_cleanup_throwsOnHTTPError() async {
        let svc = AICleanupService(config: .openAI, apiKey: "bad", transport: MockTransport(statusCode: 401))
        do { _ = try await svc.cleanup("x"); XCTFail("devrait lever") } catch { /* attendu */ }
    }
}

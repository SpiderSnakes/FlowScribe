import XCTest
@testable import FlowScribeCore

final class CloudTranscriptionEngineTests: XCTestCase {
    func test_mockTransport_returnsCannedResponse_andCapturesRequest() async throws {
        let mock = MockTransport(statusCode: 200, body: Data("ok".utf8))
        var req = URLRequest(url: URL(string: "https://example.com")!)
        req.httpMethod = "POST"
        let (data, resp) = try await mock.send(req)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "ok")
        XCTAssertEqual(resp.statusCode, 200)
        XCTAssertEqual(mock.lastRequest?.httpMethod, "POST")
    }
}

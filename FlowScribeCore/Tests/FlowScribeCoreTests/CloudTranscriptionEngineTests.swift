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

    func test_transcribeFile_buildsAuthorizedMultipartPost_andParsesText() async throws {
        let mock = MockTransport(statusCode: 200, body: Data(#"{"text":"bonjour"}"#.utf8))
        let engine = CloudTranscriptionEngine(config: .openAI, apiKey: "sk-123", transport: mock, boundary: "B")
        let url = FileManager.default.temporaryDirectory.appending(path: "clip.wav")
        try Data("RIFFDATA".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try await engine.transcribeFile(at: url, locale: Locale(identifier: "fr-FR"))

        XCTAssertEqual(text, "bonjour")
        let req = try XCTUnwrap(mock.lastRequest)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url, CloudEngineConfig.openAI.endpoint)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-123")
        XCTAssertTrue(req.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") ?? false)
        let body = String(decoding: req.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("gpt-4o-transcribe"))
        XCTAssertTrue(body.contains("filename=\"clip.wav\""))
    }

    func test_transcribeFile_throwsOnHTTPError() async {
        let mock = MockTransport(statusCode: 401, body: Data(#"{"error":"unauthorized"}"#.utf8))
        let engine = CloudTranscriptionEngine(config: .openAI, apiKey: "bad", transport: mock, boundary: "B")
        let url = FileManager.default.temporaryDirectory.appending(path: "c2.wav")
        try? Data("x".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        do { _ = try await engine.transcribeFile(at: url, locale: .current); XCTFail("devrait lever") }
        catch { /* attendu */ }
    }

    func test_validateKey_postsToTranscriptionEndpoint_andTreats422AsValid() async {
        let mock = MockTransport(statusCode: 422)
        let engine = CloudTranscriptionEngine(config: .elevenLabs, apiKey: "xi-1", transport: mock, boundary: "B")
        let r = await engine.validateKey()
        XCTAssertTrue(r.ok)              // 422 = clé authentifiée, requête incomplète (pas de fichier)
        XCTAssertEqual(r.status, 422)
        let req = mock.lastRequest
        XCTAssertEqual(req?.httpMethod, "POST")
        XCTAssertEqual(req?.url, CloudEngineConfig.elevenLabs.endpoint)
        XCTAssertEqual(req?.value(forHTTPHeaderField: "xi-api-key"), "xi-1")
    }

    func test_validateKey_invalidOn401() async {
        let engine = CloudTranscriptionEngine(config: .openAI, apiKey: "bad", transport: MockTransport(statusCode: 401), boundary: "B")
        let r = await engine.validateKey()
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.status, 401)
    }

    func test_validateKey_insufficientPermissionsOn403() async {
        let engine = CloudTranscriptionEngine(config: .elevenLabs, apiKey: "scoped", transport: MockTransport(statusCode: 403), boundary: "B")
        let r = await engine.validateKey()
        XCTAssertFalse(r.ok)
        XCTAssertEqual(r.status, 403)
    }

    func test_transcribeFile_usesModelOverride() async throws {
        let mock = MockTransport(statusCode: 200, body: Data(#"{"text":"x"}"#.utf8))
        let engine = CloudTranscriptionEngine(config: .openAI, apiKey: "k", transport: mock, modelId: "whisper-1")
        let url = FileManager.default.temporaryDirectory.appending(path: "m.wav")
        try Data("RIFF".utf8).write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        _ = try await engine.transcribeFile(at: url, locale: .current)
        let body = String(decoding: mock.lastRequest?.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("whisper-1"))
        XCTAssertFalse(body.contains("gpt-4o-transcribe"))
    }
}

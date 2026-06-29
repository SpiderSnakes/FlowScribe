import XCTest
@testable import FlowScribeCore

final class TextLLMServiceTests: XCTestCase {
    private func service(_ p: EngineProvider, _ transport: Transport) -> TextLLMService {
        TextLLMService(provider: p, model: "m", apiKey: "k", transport: transport)
    }

    func test_openAI_chatFormat_parsesContent_andAuthHeader() async throws {
        let mock = MockTransport(statusCode: 200, body: Data(#"{"choices":[{"message":{"content":"corrigé"}}]}"#.utf8))
        let out = try await service(.openAI, mock).complete(system: "s", user: "u")
        XCTAssertEqual(out, "corrigé")
        XCTAssertEqual(mock.lastRequest?.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(mock.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer k")
    }

    func test_mistral_usesMistralEndpoint() async throws {
        let mock = MockTransport(statusCode: 200, body: Data(#"{"choices":[{"message":{"content":"ok"}}]}"#.utf8))
        _ = try await service(.mistral, mock).complete(system: "s", user: "u")
        XCTAssertEqual(mock.lastRequest?.url?.absoluteString, "https://api.mistral.ai/v1/chat/completions")
    }

    func test_anthropic_messagesFormat_parsesText_andApiKeyHeader() async throws {
        let mock = MockTransport(statusCode: 200, body: Data(#"{"content":[{"type":"text","text":"corrigé"}]}"#.utf8))
        let out = try await service(.anthropic, mock).complete(system: "s", user: "u")
        XCTAssertEqual(out, "corrigé")
        XCTAssertEqual(mock.lastRequest?.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(mock.lastRequest?.value(forHTTPHeaderField: "x-api-key"), "k")
        XCTAssertEqual(mock.lastRequest?.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
    }

    func test_google_generateContent_parsesText_andKeyInHeaderNotURL() async throws {
        let mock = MockTransport(statusCode: 200, body: Data(#"{"candidates":[{"content":{"parts":[{"text":"corrigé"}]}}]}"#.utf8))
        let out = try await service(.google, mock).complete(system: "s", user: "u")
        XCTAssertEqual(out, "corrigé")
        let url = mock.lastRequest?.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("generativelanguage.googleapis.com"))
        // Sécurité : la clé passe par l'en-tête x-goog-api-key, JAMAIS dans l'URL (sinon elle fuiterait
        // via NSErrorFailingURLStringKey dans les logs d'erreur).
        XCTAssertEqual(mock.lastRequest?.value(forHTTPHeaderField: "x-goog-api-key"), "k")
        XCTAssertFalse(url.contains("key=k"), "la clé ne doit pas être dans l'URL")
    }

    func test_httpError_throws() async {
        let mock = MockTransport(statusCode: 401, body: Data("nope".utf8))
        do { _ = try await service(.openAI, mock).complete(system: "s", user: "u"); XCTFail("devrait lever") }
        catch { /* attendu */ }
    }

    func test_unsupportedProvider_throws() async {
        let mock = MockTransport(statusCode: 200, body: Data())
        do { _ = try await service(.elevenLabs, mock).complete(system: "s", user: "u"); XCTFail("devrait lever") }
        catch { /* attendu */ }
    }
}

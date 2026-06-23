import XCTest
@testable import FlowScribeCore

final class EngineProviderTests: XCTestCase {
    func test_configs_haveExpectedAuthAndModelFields() {
        XCTAssertEqual(CloudEngineConfig.openAI.authHeaderName, "Authorization")
        XCTAssertEqual(CloudEngineConfig.openAI.modelField, "model")
        XCTAssertEqual(CloudEngineConfig.elevenLabs.authHeaderName, "xi-api-key")
        XCTAssertEqual(CloudEngineConfig.elevenLabs.modelField, "model_id")
        XCTAssertEqual(CloudEngineConfig.mistral.authValuePrefix, "Bearer ")
        XCTAssertTrue(CloudEngineConfig.openAI.pricePerMinuteUSD > 0)
        XCTAssertEqual(CloudEngineConfig.elevenLabs.modelValue, "scribe_v2")
    }

    func test_appleProvider_buildsLocalEngine_withoutKey() {
        let engine = EngineProvider.appleLocal.makeEngine(apiKey: nil, transport: MockTransport())
        XCTAssertEqual(engine?.id, "apple.local")
        XCTAssertNil(EngineProvider.appleLocal.secretKey)
    }

    func test_cloudProvider_requiresKey() {
        XCTAssertNil(EngineProvider.openAI.makeEngine(apiKey: nil, transport: MockTransport()))
        let e = EngineProvider.openAI.makeEngine(apiKey: "sk", transport: MockTransport())
        XCTAssertEqual(e?.id, CloudEngineConfig.openAI.id)
    }
}

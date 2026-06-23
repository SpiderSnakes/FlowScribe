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
    }
}

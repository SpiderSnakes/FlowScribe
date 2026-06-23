import XCTest
@testable import FlowScribeCore

final class PostCorrectorTests: XCTestCase {
    func test_profileStore_perEngine_roundTrip() {
        let store = InMemoryCorrectionProfileStore()
        store.add(CorrectionRule(heard: "doi", replacement: "Dokploy"), for: "apple.local")
        store.add(CorrectionRule(heard: "doc ploy", replacement: "Dokploy"), for: "elevenlabs.scribe")
        XCTAssertEqual(store.rules(for: "apple.local"), [CorrectionRule(heard: "doi", replacement: "Dokploy")])
        XCTAssertEqual(store.rules(for: "elevenlabs.scribe").first?.replacement, "Dokploy")
        XCTAssertTrue(store.rules(for: "openai.gpt-4o-transcribe").isEmpty)
    }
}

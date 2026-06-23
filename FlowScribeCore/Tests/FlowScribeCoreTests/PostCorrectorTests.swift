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

    func test_postCorrector_replacesHeardWithCanonical_caseInsensitive() {
        let store = InMemoryCorrectionProfileStore()
        store.add(CorrectionRule(heard: "doi", replacement: "Dokploy"), for: "apple.local")
        let pc = PostCorrector(store: store)
        XCTAssertEqual(pc.correct("On parle de Doi en prod.", engineId: "apple.local"),
                       "On parle de Dokploy en prod.")
    }

    func test_postCorrector_multiWordHeard() {
        let store = InMemoryCorrectionProfileStore()
        store.add(CorrectionRule(heard: "doc ploy", replacement: "Dokploy"), for: "elevenlabs.scribe")
        let pc = PostCorrector(store: store)
        XCTAssertEqual(pc.correct("déployer sur Doc Ploy demain", engineId: "elevenlabs.scribe"),
                       "déployer sur Dokploy demain")
    }

    func test_postCorrector_noRules_returnsUnchanged() {
        let pc = PostCorrector(store: InMemoryCorrectionProfileStore())
        XCTAssertEqual(pc.correct("rien à corriger", engineId: "x"), "rien à corriger")
    }
}

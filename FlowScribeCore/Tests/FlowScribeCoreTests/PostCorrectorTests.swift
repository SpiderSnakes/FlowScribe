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

    func test_postCorrector_skipsDisabledRule() {
        let store = InMemoryCorrectionProfileStore()
        store.setRules([CorrectionRule(heard: "doi", replacement: "Dokploy", enabled: false)], for: "apple.local")
        let pc = PostCorrector(store: store)
        XCTAssertEqual(pc.correct("parle de Doi.", engineId: "apple.local"), "parle de Doi.")
    }

    func test_postCorrector_appliesGlobalRulesAcrossEngines() {
        let store = InMemoryCorrectionProfileStore()
        store.add(CorrectionRule(heard: "doi", replacement: "Dokploy"), for: CorrectionScope.global)
        let pc = PostCorrector(store: store)
        XCTAssertEqual(pc.correct("Doi ici", engineId: "apple.local"), "Dokploy ici")
        XCTAssertEqual(pc.correct("Doi là", engineId: "mistral.voxtral"), "Dokploy là")
    }

    func test_add_dedupsByHeard_caseInsensitive_keepsExisting() {
        let store = InMemoryCorrectionProfileStore()
        store.add(CorrectionRule(heard: "doi", replacement: "Dokploy", enabled: false), for: "apple.local")
        store.add(CorrectionRule(heard: "DOI", replacement: "Autre", enabled: true), for: "apple.local")
        let rules = store.rules(for: "apple.local")
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first, CorrectionRule(heard: "doi", replacement: "Dokploy", enabled: false))
    }

    func test_correctionRule_decodesLegacyJSON_enabledDefaultsTrue() throws {
        let legacy = Data(#"{"heard":"doi","replacement":"Dokploy"}"#.utf8)
        let rule = try JSONDecoder().decode(CorrectionRule.self, from: legacy)
        XCTAssertTrue(rule.enabled)
        XCTAssertEqual(rule, CorrectionRule(heard: "doi", replacement: "Dokploy"))
    }
}

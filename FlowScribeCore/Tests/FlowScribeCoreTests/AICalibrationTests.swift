import XCTest
@testable import FlowScribeCore

final class AICalibrationTests: XCTestCase {
    func test_parses_cleanJSONArray() {
        let r = #"[{"heard":"Doc Ploy","corrected":"Dokploy","occurrences":3}]"#
        let p = AICalibration.parseProposals(from: r)
        XCTAssertEqual(p, [CorrectionProposal(heard: "Doc Ploy", corrected: "Dokploy", occurrences: 3)])
    }

    func test_parses_whenWrappedInProseOrFences() {
        let r = "Voici mes propositions :\n```json\n[{\"heard\":\"Doy\",\"corrected\":\"Dokploy\"}]\n```\nVoilà."
        let p = AICalibration.parseProposals(from: r)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p.first?.corrected, "Dokploy")
        XCTAssertEqual(p.first?.occurrences, 1)   // défaut quand absent
    }

    func test_emptyArray_givesNoProposals() {
        XCTAssertTrue(AICalibration.parseProposals(from: "[]").isEmpty)
    }

    func test_garbage_givesNoProposals() {
        XCTAssertTrue(AICalibration.parseProposals(from: "désolé, aucune idée").isEmpty)
    }

    func test_filtersIdenticalAndEmpty() {
        let r = #"[{"heard":"ok","corrected":"ok"},{"heard":"","corrected":"x"},{"heard":"Doi","corrected":"Dokploy"}]"#
        let p = AICalibration.parseProposals(from: r)
        XCTAssertEqual(p.map(\.corrected), ["Dokploy"])
    }

    func test_propose_usesLLM_andParses() async {
        let mock = MockTransport(statusCode: 200,
            body: Data(#"{"choices":[{"message":{"content":"[{\"heard\":\"Doc Ploy\",\"corrected\":\"Dokploy\",\"occurrences\":2}]"}}]}"#.utf8))
        let p = await AICalibration.propose(transcriptions: ["déployer sur Doc Ploy"],
                                            provider: .openAI, model: "gpt-4o-mini", apiKey: "k", transport: mock)
        XCTAssertEqual(p, [CorrectionProposal(heard: "Doc Ploy", corrected: "Dokploy", occurrences: 2)])
    }
}

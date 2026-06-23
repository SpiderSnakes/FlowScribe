import XCTest
@testable import FlowScribeCore

final class CalibrationServiceTests: XCTestCase {
    func test_proposes_singleTokenMishearing() {
        let rules = CalibrationService.proposeRules(
            reference: "On parle de Dokploy aujourd'hui.",
            hypothesis: "On parle de Doi aujourd'hui.",
            glossary: ["Dokploy"])
        XCTAssertEqual(rules, [CorrectionRule(heard: "doi", replacement: "Dokploy")])
    }
    func test_proposes_multiTokenMishearing() {
        let rules = CalibrationService.proposeRules(
            reference: "déployer sur Dokploy",
            hypothesis: "déployer sur Doc Ploy",
            glossary: ["Dokploy"])
        XCTAssertEqual(rules, [CorrectionRule(heard: "doc ploy", replacement: "Dokploy")])
    }
    func test_ignoresNonGlossaryDifferences() {
        let rules = CalibrationService.proposeRules(
            reference: "bonjour le monde",
            hypothesis: "bonsoir le monde",
            glossary: ["Dokploy"])
        XCTAssertTrue(rules.isEmpty)
    }
}

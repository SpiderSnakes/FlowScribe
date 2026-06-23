import XCTest
@testable import FlowScribeCore

final class AlignerTests: XCTestCase {
    func test_tokenize_lowercasesAndStripsPunctuation() {
        XCTAssertEqual(Aligner.tokenize("Bonjour, Dokploy!"), ["bonjour", "dokploy"])
    }
    func test_align_substitution() {
        let pairs = Aligner.align(reference: ["dokploy"], hypothesis: ["doi"])
        XCTAssertEqual(pairs, [AlignedPair(reference: "dokploy", hypothesis: "doi")])
    }
    func test_align_identical() {
        let pairs = Aligner.align(reference: ["a", "b"], hypothesis: ["a", "b"])
        XCTAssertEqual(pairs, [AlignedPair(reference: "a", hypothesis: "a"),
                               AlignedPair(reference: "b", hypothesis: "b")])
    }
    func test_align_insertion_splitWord() {
        let pairs = Aligner.align(reference: ["dokploy"], hypothesis: ["doc", "ploy"])
        XCTAssertTrue(pairs.contains(AlignedPair(reference: "dokploy", hypothesis: "doc")))
        XCTAssertTrue(pairs.contains(AlignedPair(reference: nil, hypothesis: "ploy")))
    }
}

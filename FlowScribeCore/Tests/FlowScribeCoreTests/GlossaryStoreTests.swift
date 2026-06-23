import XCTest
@testable import FlowScribeCore

final class GlossaryStoreTests: XCTestCase {
    func test_addRemove_dedupCaseInsensitive() {
        let g = InMemoryGlossaryStore()
        g.add("Dokploy"); g.add("dokploy"); g.add("SwiftUI")
        XCTAssertEqual(g.terms.count, 2)
        g.remove("dokploy")
        XCTAssertEqual(g.terms, ["SwiftUI"])
    }
}

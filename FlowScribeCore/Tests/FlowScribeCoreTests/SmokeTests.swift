import XCTest
@testable import FlowScribeCore

final class SmokeTests: XCTestCase {
    func test_capabilities_storesValues() {
        let caps = EngineCapabilities(supportsStreaming: true, supportsKeyterms: false, isLocal: true)
        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertFalse(caps.supportsKeyterms)
        XCTAssertTrue(caps.isLocal)
    }
}

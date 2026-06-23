import XCTest
@testable import FlowScribeCore

final class PressClassifierTests: XCTestCase {
    func test_shortPress_isTap() {
        XCTAssertEqual(PressClassifier.classify(pressDuration: 0.10, holdThreshold: 0.25), .tap)
    }
    func test_longPress_isHold() {
        XCTAssertEqual(PressClassifier.classify(pressDuration: 0.80, holdThreshold: 0.25), .hold)
    }
    func test_exactlyAtThreshold_isHold() {
        XCTAssertEqual(PressClassifier.classify(pressDuration: 0.25, holdThreshold: 0.25), .hold)
    }
}

import XCTest
@testable import FlowScribeCore

final class CostEstimatorTests: XCTestCase {
    func test_estimate_scalesWithDuration() {
        XCTAssertEqual(CostEstimator.estimateUSD(durationSeconds: 120, pricePerMinuteUSD: 0.006), 0.012, accuracy: 1e-9)
        XCTAssertEqual(CostEstimator.estimateUSD(durationSeconds: 0, pricePerMinuteUSD: 0.006), 0, accuracy: 1e-9)
    }
    func test_formatted_showsFourDecimals() {
        XCTAssertEqual(CostEstimator.formatted(0.012), "$0.0120")
    }
}

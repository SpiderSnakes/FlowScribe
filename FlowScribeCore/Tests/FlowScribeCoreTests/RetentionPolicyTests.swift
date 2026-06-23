import XCTest
@testable import FlowScribeCore

final class RetentionPolicyTests: XCTestCase {
    private func rec(_ ageDays: Double) -> TranscriptionRecord {
        TranscriptionRecord(id: UUID(), date: Date(timeIntervalSinceNow: -ageDays * 86_400),
                            text: "t", engineId: "e", locale: "fr-FR", audioFileName: "a.caf", duration: 1)
    }
    func test_maxAgeZero_neverExpires() {
        XCTAssertTrue(RetentionPolicy.expired([rec(100)], now: Date(), maxAgeDays: 0).isEmpty)
    }
    func test_expiresBeyondMaxAge() {
        let old = rec(40), young = rec(5)
        let expired = RetentionPolicy.expired([old, young], now: Date(), maxAgeDays: 30)
        XCTAssertEqual(expired.map(\.id), [old.id])
    }
}

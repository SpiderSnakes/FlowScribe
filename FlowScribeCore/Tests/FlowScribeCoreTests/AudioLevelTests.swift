import XCTest
@testable import FlowScribeCore

final class AudioLevelTests: XCTestCase {
    func test_empty_isZero() { XCTAssertEqual(AudioLevel.rms([]), 0, accuracy: 1e-6) }
    func test_silence_isZero() { XCTAssertEqual(AudioLevel.rms([0, 0, 0, 0]), 0, accuracy: 1e-6) }
    func test_fullScale_isOne() { XCTAssertEqual(AudioLevel.rms([1, -1, 1, -1]), 1, accuracy: 1e-6) }
    func test_louder_isHigher() {
        XCTAssertGreaterThan(AudioLevel.rms([0.5, -0.5]), AudioLevel.rms([0.1, -0.1]))
    }
    func test_clampedToOne() { XCTAssertEqual(AudioLevel.rms([4, -4]), 1, accuracy: 1e-6) }
}

import XCTest
@testable import FlowScribeCore

final class HistoryStoreTests: XCTestCase {
    private func rec(_ id: UUID, _ ageSec: Double) -> TranscriptionRecord {
        TranscriptionRecord(id: id, date: Date(timeIntervalSinceNow: -ageSec), text: "t",
                            engineId: "e", locale: "fr-FR", audioFileName: "\(id).caf", duration: 1)
    }
    func test_add_sortsNewestFirst_andDelete() {
        let store = InMemoryHistoryStore()
        let older = UUID(), newer = UUID()
        store.add(rec(older, 100)); store.add(rec(newer, 1))
        XCTAssertEqual(store.records.map(\.id), [newer, older])
        store.delete(id: older)
        XCTAssertEqual(store.records.map(\.id), [newer])
    }
}

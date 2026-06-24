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

    func test_update_replacesInPlace_noDuplicate() {
        let store = InMemoryHistoryStore()
        let id = UUID()
        store.add(rec(id, 10))
        var updated = rec(id, 10)
        updated = TranscriptionRecord(id: id, date: updated.date, text: "corrigé",
                                      engineId: "e2", locale: "fr-FR", audioFileName: updated.audioFileName, duration: 1)
        store.update(updated)
        XCTAssertEqual(store.records.count, 1)            // pas de doublon
        XCTAssertEqual(store.records.first?.text, "corrigé")
        XCTAssertEqual(store.records.first?.engineId, "e2")
    }
}

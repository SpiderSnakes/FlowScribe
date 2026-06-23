import XCTest
@testable import FlowScribeCore

final class ModeStoreTests: XCTestCase {
    private func sample(_ name: String) -> Mode {
        Mode(name: name, provider: .appleLocal, modelId: "apple",
             localeIdentifier: "fr-FR", pauseMusic: true, cleanupPrompt: nil)
    }

    func test_upsert_addsThenReplaces() {
        let store = InMemoryModeStore()
        var m = sample("E-mail")
        store.upsert(m)
        XCTAssertEqual(store.modes.count, 1)
        m.name = "E-mail pro"
        store.upsert(m)
        XCTAssertEqual(store.modes.count, 1)
        XCTAssertEqual(store.modes.first?.name, "E-mail pro")
    }

    func test_setActive_onlyIfExists() {
        let store = InMemoryModeStore()
        let m = sample("Notes")
        store.upsert(m)
        store.setActive(m.id)
        XCTAssertEqual(store.activeModeId, m.id)
        store.setActive(UUID())   // id inconnu → ignoré
        XCTAssertEqual(store.activeModeId, m.id)
    }

    func test_delete_reassignsActive() {
        let store = InMemoryModeStore()
        let a = sample("A"); let b = sample("B")
        store.upsert(a); store.upsert(b)
        store.setActive(a.id)
        store.delete(id: a.id)
        XCTAssertEqual(store.modes.count, 1)
        XCTAssertEqual(store.activeModeId, b.id)   // bascule sur un mode restant
    }

    func test_json_roundTrip() throws {
        let url = URL.temporaryDirectory.appending(path: "modes-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = JSONModeStore(url: url)
        let m = Mode(name: "Code", provider: .openAI, modelId: "gpt-4o-transcribe",
                     localeIdentifier: "en-US", pauseMusic: false, cleanupPrompt: "Formate en markdown.")
        store.upsert(m)
        store.setActive(m.id)
        let reloaded = JSONModeStore(url: url)
        XCTAssertEqual(reloaded.modes, [m])
        XCTAssertEqual(reloaded.activeModeId, m.id)
    }
}

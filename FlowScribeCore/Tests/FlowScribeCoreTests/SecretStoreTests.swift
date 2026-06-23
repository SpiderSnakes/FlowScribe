import XCTest
@testable import FlowScribeCore

final class SecretStoreTests: XCTestCase {
    func test_inMemory_setGetDelete() {
        let store = InMemorySecretStore()
        XCTAssertNil(store.get("openai"))
        store.set("sk-123", for: "openai")
        XCTAssertEqual(store.get("openai"), "sk-123")
        store.set(nil, for: "openai")
        XCTAssertNil(store.get("openai"))
    }
}

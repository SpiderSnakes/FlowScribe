import XCTest
@testable import FlowScribeCore

final class AppLogTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Pointe le log vers un dossier temporaire unique (pas de pollution de l'Application Support réel).
        AppLog.fileURL = FileManager.default.temporaryDirectory
            .appending(path: "flowscribe-applog-\(UUID().uuidString)/flowscribe.log")
    }

    func test_write_read_clear() {
        AppLog.info("Test", "bonjour")
        AppLog.error("Test", "boum \(42)")
        let content = AppLog.read()
        XCTAssertTrue(content.contains("[INFO] [Test] bonjour"), content)
        XCTAssertTrue(content.contains("[ERROR] [Test] boum 42"), content)
        AppLog.clear()
        XCTAssertEqual(AppLog.read(), "")
    }
}

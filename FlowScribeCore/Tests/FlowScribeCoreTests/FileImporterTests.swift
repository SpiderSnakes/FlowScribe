import XCTest
@testable import FlowScribeCore

final class FileImporterTests: XCTestCase {
    func test_preservesExtension() {
        let id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let name = FileImporter.importedFileName(for: URL(filePath: "/x/podcast.MP3"), id: id)
        XCTAssertEqual(name, "11111111-1111-1111-1111-111111111111.mp3")
    }

    func test_noExtension_usesUUIDOnly() {
        let id = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let name = FileImporter.importedFileName(for: URL(filePath: "/x/recording"), id: id)
        XCTAssertEqual(name, "22222222-2222-2222-2222-222222222222")
    }

    func test_distinctIds_giveDistinctNames() {
        let a = FileImporter.importedFileName(for: URL(filePath: "/x/a.wav"), id: UUID())
        let b = FileImporter.importedFileName(for: URL(filePath: "/x/a.wav"), id: UUID())
        XCTAssertNotEqual(a, b)
    }
}

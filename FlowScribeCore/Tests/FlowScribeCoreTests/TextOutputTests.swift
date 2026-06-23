import XCTest
import AppKit
@testable import FlowScribeCore

final class TextOutputTests: XCTestCase {
    func test_clipboard_writesString() {
        let pb = NSPasteboard(name: NSPasteboard.Name("FlowScribeTest"))
        pb.clearContents()
        Clipboard.write("café été", to: pb)
        XCTAssertEqual(pb.string(forType: .string), "café été")
    }
}

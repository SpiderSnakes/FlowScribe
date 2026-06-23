import XCTest
@testable import FlowScribeCore

final class MultipartFormDataTests: XCTestCase {
    func test_buildsBodyWithFieldAndFile() {
        var form = MultipartFormData(boundary: "BOUNDARY")
        form.addField(name: "model", value: "gpt-4o-transcribe")
        form.addFile(name: "file", filename: "a.wav", contentType: "audio/wav", data: Data("RIFF".utf8))
        let body = String(decoding: form.encoded(), as: UTF8.self)
        XCTAssertEqual(form.contentType, "multipart/form-data; boundary=BOUNDARY")
        XCTAssertTrue(body.contains("name=\"model\""))
        XCTAssertTrue(body.contains("gpt-4o-transcribe"))
        XCTAssertTrue(body.contains("filename=\"a.wav\""))
        XCTAssertTrue(body.contains("Content-Type: audio/wav"))
        XCTAssertTrue(body.hasSuffix("--BOUNDARY--\r\n"))
    }
}

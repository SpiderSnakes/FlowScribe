import Foundation

public struct MultipartFormData {
    private let boundary: String
    private var body = Data()
    public init(boundary: String) { self.boundary = boundary }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(Self.header(name))\"\r\n\r\n")
        append("\(value)\r\n")
    }

    public mutating func addFile(name: String, filename: String, contentType: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(Self.header(name))\"; filename=\"\(Self.header(filename))\"\r\n")
        append("Content-Type: \(Self.header(contentType))\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    /// Neutralise les guillemets et les sauts de ligne dans une valeur d'en-tête (anti-injection CRLF).
    private static func header(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
    }

    public func encoded() -> Data {
        var out = body
        out.append(Data("--\(boundary)--\r\n".utf8))
        return out
    }

    private mutating func append(_ string: String) { body.append(Data(string.utf8)) }
}

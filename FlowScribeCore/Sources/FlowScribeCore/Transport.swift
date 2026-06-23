import Foundation

public protocol Transport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: Transport {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

/// Transport de test : renvoie une réponse programmée et capture la requête.
public final class MockTransport: Transport, @unchecked Sendable {
    public private(set) var lastRequest: URLRequest?
    private let statusCode: Int
    private let body: Data
    private let error: Error?
    public init(statusCode: Int = 200, body: Data = Data(), error: Error? = nil) {
        self.statusCode = statusCode; self.body = body; self.error = error
    }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        if let error { throw error }
        let resp = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (body, resp)
    }
}

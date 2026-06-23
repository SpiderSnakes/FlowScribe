import Foundation

public struct CorrectionRule: Codable, Equatable, Sendable {
    public let heard: String
    public let replacement: String
    public init(heard: String, replacement: String) {
        self.heard = heard; self.replacement = replacement
    }
}

import Foundation

public protocol TextOutput: Sendable {
    func deliver(_ text: String)
}

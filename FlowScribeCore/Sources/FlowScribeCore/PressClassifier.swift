import Foundation

public enum PressKind: Equatable, Sendable { case tap, hold }

public enum PressClassifier {
    /// Un appui >= seuil est un "maintien" (push-to-talk), sinon un "tap" (bascule).
    public static func classify(pressDuration: TimeInterval, holdThreshold: TimeInterval) -> PressKind {
        pressDuration >= holdThreshold ? .hold : .tap
    }
}

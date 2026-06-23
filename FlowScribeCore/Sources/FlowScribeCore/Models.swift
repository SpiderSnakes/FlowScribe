import Foundation

/// Résultat d'un segment de transcription (utilisé en streaming plus tard).
public struct TranscriptResult: Equatable, Sendable {
    public let text: String
    public let isFinal: Bool
    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

/// Capacités déclarées par un moteur de transcription.
public struct EngineCapabilities: Equatable, Sendable {
    public let supportsStreaming: Bool
    public let supportsKeyterms: Bool
    public let isLocal: Bool
    public init(supportsStreaming: Bool, supportsKeyterms: Bool, isLocal: Bool) {
        self.supportsStreaming = supportsStreaming
        self.supportsKeyterms = supportsKeyterms
        self.isLocal = isLocal
    }
}

/// Un enregistrement audio sur disque.
public struct AudioRecording: Equatable, Sendable {
    public let url: URL
    public let duration: TimeInterval?
    public init(url: URL, duration: TimeInterval?) {
        self.url = url
        self.duration = duration
    }
}

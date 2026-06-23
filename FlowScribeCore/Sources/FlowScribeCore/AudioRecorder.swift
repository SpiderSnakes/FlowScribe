import Foundation
import AVFoundation

public protocol AudioRecorder: Sendable {
    func start() throws
    func stop() async -> AudioRecording
}

/// Enregistre le micro vers un fichier CAF (robuste au crash, écriture incrémentale)
/// et publie le niveau de voix (RMS 0→1) en direct via `onLevel`.
public final class MicrophoneRecorder: AudioRecorder, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let outputDirectory: URL
    private var file: AVAudioFile?
    private var currentURL: URL?
    private var startedAt: Date?

    /// Niveau de voix live (RMS 0→1) pendant l'enregistrement.
    public var onLevel: (@Sendable (Float) -> Void)?

    public init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    public func start() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let url = outputDirectory.appending(path: "rec-\(Int(Date().timeIntervalSince1970)).caf")
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        let levelHandler = onLevel
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            try? audioFile.write(from: buffer)
            guard let levelHandler, let ch = buffer.floatChannelData else { return }
            let n = Int(buffer.frameLength)
            let level = AudioLevel.rms(Array(UnsafeBufferPointer(start: ch[0], count: n)))
            DispatchQueue.main.async { levelHandler(level) }
        }
        engine.prepare()
        try engine.start()
        self.file = audioFile
        self.currentURL = url
        self.startedAt = Date()
    }

    public func stop() async -> AudioRecording {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let url = currentURL ?? outputDirectory.appending(path: "empty.caf")
        let duration = startedAt.map { Date().timeIntervalSince($0) }
        file = nil; currentURL = nil; startedAt = nil
        return AudioRecording(url: url, duration: duration)
    }
}

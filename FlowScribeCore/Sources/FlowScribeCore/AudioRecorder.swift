import Foundation
import AVFoundation

public protocol AudioRecorder: Sendable {
    func start() throws
    func stop() async -> AudioRecording
}

/// Enregistre le micro vers un fichier CAF (robuste au crash, écriture incrémentale).
public final class MicrophoneRecorder: AudioRecorder, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let outputDirectory: URL
    private var file: AVAudioFile?
    private var currentURL: URL?
    private var startedAt: Date?

    public init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    public func start() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let url = outputDirectory.appending(path: "rec-\(Int(Date().timeIntervalSince1970)).caf")
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            try? audioFile.write(from: buffer)
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

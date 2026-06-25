import Foundation
import AVFoundation
import CoreAudio

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
    private var configObserver: NSObjectProtocol?
    /// Mis à `true` si une écriture de buffer échoue ou si la config audio change en cours d'enregistrement
    /// (route/format) — l'audio peut alors être tronqué. Journalisé à l'arrêt.
    private nonisolated(unsafe) var writeFailed = false

    /// Niveau de voix live (RMS 0→1) pendant l'enregistrement.
    public var onLevel: (@Sendable (Float) -> Void)?
    /// UID du micro à utiliser (vide/nil = micro système par défaut). Pris en compte au prochain `start()`.
    public var preferredDeviceUID: String?

    public init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    public func start() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let url = outputDirectory.appending(path: "rec-\(Int(Date().timeIntervalSince1970)).caf")
        let input = engine.inputNode
        // Route vers le micro choisi (sinon micro système par défaut).
        if let uid = preferredDeviceUID, !uid.isEmpty,
           let devID = CoreAudioDevices.deviceID(forUID: uid), let au = input.audioUnit {
            var dev = devID
            AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        let format = input.outputFormat(forBus: 0)
        AppLog.info("AudioRecorder", "start \(url.lastPathComponent) — \(Int(format.sampleRate))Hz \(format.channelCount)ch")
        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        let levelHandler = onLevel
        writeFailed = false
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            do { try audioFile.write(from: buffer) } catch { self?.writeFailed = true }
            guard let levelHandler, let ch = buffer.floatChannelData else { return }
            let n = Int(buffer.frameLength)
            let level = AudioLevel.rms(Array(UnsafeBufferPointer(start: ch[0], count: n)))
            DispatchQueue.main.async { levelHandler(level) }
        }
        // La config audio peut changer en cours d'enregistrement (changement de route/périphérique,
        // bascule d'espace plein écran…), ce qui casse le format figé du fichier → on le journalise.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.writeFailed = true
            AppLog.warn("AudioRecorder", "changement de configuration audio pendant l'enregistrement (route/format)")
        }
        engine.prepare()
        try engine.start()
        self.file = audioFile
        self.currentURL = url
        self.startedAt = Date()
    }

    public func stop() async -> AudioRecording {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let url = currentURL ?? outputDirectory.appending(path: "empty.caf")
        let duration = startedAt.map { Date().timeIntervalSince($0) }
        file = nil   // libère la dernière référence → l'AVAudioFile écrit ses en-têtes/flush sur disque
        currentURL = nil; startedAt = nil
        let durStr = duration.map { String(format: "%.1fs", $0) } ?? "?"
        if writeFailed {
            AppLog.warn("AudioRecorder", "stop \(url.lastPathComponent) (\(durStr)) — écriture incomplète possible (config/route a changé)")
        } else {
            AppLog.info("AudioRecorder", "stop \(url.lastPathComponent) (\(durStr))")
        }
        return AudioRecording(url: url, duration: duration)
    }
}

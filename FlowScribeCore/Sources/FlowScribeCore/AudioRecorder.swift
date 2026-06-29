import Foundation
import AVFoundation
import CoreAudio
import Accelerate
import Synchronization

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
    /// `true` si une écriture de buffer échoue ou si la config audio change en cours d'enregistrement
    /// (route/format) — l'audio peut alors être tronqué. `Atomic` : écrit sans verrou depuis le thread audio
    /// temps réel + le thread de notification, lu sur le thread principal (lock-free, sûr).
    private let writeFailed = Atomic<Bool>(false)

    /// Niveau de voix live (RMS 0→1) pendant l'enregistrement.
    public var onLevel: (@Sendable (Float) -> Void)?
    /// Signalé en temps réel si la config audio change en cours d'enregistrement (route/format) : l'audio
    /// capturé après ce point peut être tronqué. Permet à l'UI d'avertir l'utilisateur sans attendre `stop()`.
    public var onTruncated: (@Sendable () -> Void)?
    /// UID du micro à utiliser (vide/nil = micro système par défaut). Pris en compte au prochain `start()`.
    public var preferredDeviceUID: String?

    public init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    public func start() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        // CAF : conteneur robuste à une interruption/crash — écriture incrémentale en flux, sans en-tête
        // à finaliser. (Le WAV/RIFF fige la taille dans son en-tête au moment de la fermeture propre ;
        // un crash en cours laisserait un WAV illisible « 0 octet ».) On enregistre donc en CAF, puis on
        // convertit en WAV VÉRIFIÉ à l'arrêt (cf. AudioConverter) — format accepté par TOUS les
        // fournisseurs (OpenAI/Mistral rejettent le .caf) sans jamais risquer de perdre l'audio capturé.
        let url = outputDirectory.appending(path: "rec-\(Int(Date().timeIntervalSince1970)).caf")
        let input = engine.inputNode
        // Route vers le micro choisi (sinon micro système par défaut). On journalise tout échec de
        // routage : sans ça, un micro choisi indisponible (débranché…) replie silencieusement sur le
        // micro système et l'utilisateur croit dicter dans le mauvais micro.
        if let uid = preferredDeviceUID, !uid.isEmpty {
            if let devID = CoreAudioDevices.deviceID(forUID: uid), let au = input.audioUnit {
                var dev = devID
                let status = AudioUnitSetProperty(au, kAudioOutputUnitProperty_CurrentDevice,
                                                  kAudioUnitScope_Global, 0, &dev, UInt32(MemoryLayout<AudioDeviceID>.size))
                if status != noErr {
                    AppLog.warn("AudioRecorder", "échec du routage vers le micro choisi (status \(status)) — repli sur le micro système par défaut")
                }
            } else {
                AppLog.warn("AudioRecorder", "micro choisi indisponible (\(uid)) — repli sur le micro système par défaut")
            }
        }
        let format = input.outputFormat(forBus: 0)
        AppLog.info("AudioRecorder", "start \(url.lastPathComponent) — \(Int(format.sampleRate))Hz \(format.channelCount)ch")
        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        let levelHandler = onLevel
        writeFailed.store(false, ordering: .relaxed)
        // Le tap est installé APRÈS un démarrage réussi de l'engine : `installTap` enregistre le tap
        // immédiatement (avant tout `start()`), donc si `start()` levait après l'installation, le tap
        // resterait sur le bus 0 et le prochain `start()` (réutilisation de l'instance, ex. « Recommencer »)
        // déclencherait l'exception AVFoundation « only one tap may be installed on any bus » → crash.
        // On démarre d'abord, puis on tappe ; en cas d'échec on nettoie le bus avant de propager l'erreur.
        engine.prepare()
        do {
            try engine.start()
        } catch {
            engine.stop()
            throw error
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            do { try audioFile.write(from: buffer) } catch { self?.writeFailed.store(true, ordering: .relaxed) }
            guard let levelHandler, let ch = buffer.floatChannelData else { return }
            let n = Int(buffer.frameLength)
            // RMS calculé directement sur le pointeur (Accelerate), sans `Array(...)` : on évite une
            // allocation/copie heap par buffer sur le thread audio temps réel (déconseillée — risque de glitch).
            var meanSquares: Float = 0
            vDSP_measqv(ch[0], 1, &meanSquares, vDSP_Length(n))
            let level = min(1, max(0, meanSquares.squareRoot()))
            DispatchQueue.main.async { levelHandler(level) }
        }
        // Observateur installé seulement APRÈS un démarrage réussi (sinon il fuiterait si start() lève).
        // La config audio peut changer en cours d'enregistrement (route/périphérique, bascule d'espace
        // plein écran…), ce qui casse le format figé du fichier → on le journalise.
        let truncatedHandler = onTruncated
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil) { [weak self] _ in
            self?.writeFailed.store(true, ordering: .relaxed)
            AppLog.warn("AudioRecorder", "changement de configuration audio pendant l'enregistrement (route/format)")
            // Avertit l'UI en temps réel : seul le début aura pu être capturé proprement.
            truncatedHandler?()
        }
        self.file = audioFile
        self.currentURL = url
        self.startedAt = Date()
    }

    public func stop() async -> AudioRecording {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let cafURL = currentURL ?? outputDirectory.appending(path: "empty.caf")
        let duration = startedAt.map { Date().timeIntervalSince($0) }
        file = nil   // libère la dernière référence → le CAF est flushé sur disque
        currentURL = nil; startedAt = nil
        let durStr = duration.map { String(format: "%.1fs", $0) } ?? "?"
        let bytes = (try? FileManager.default.attributesOfItem(atPath: cafURL.path))?[.size] as? Int
        let sizeStr = bytes.map { "\($0 / 1024) Ko" } ?? "?"
        if writeFailed.load(ordering: .relaxed) {
            AppLog.warn("AudioRecorder", "stop \(cafURL.lastPathComponent) (\(durStr), \(sizeStr)) — écriture incomplète possible (config/route a changé)")
        } else {
            AppLog.info("AudioRecorder", "stop \(cafURL.lastPathComponent) (\(durStr), \(sizeStr))")
        }
        // Conversion CAF → WAV hors du thread appelant (lecture + réécriture disque). Le CAF n'est
        // supprimé QU'APRÈS vérification du WAV produit ; si la conversion échoue, on conserve le CAF
        // (jamais de perte d'audio — quitte à transcrire le CAF tel quel via le repli ElevenLabs).
        let wavURL = await Task.detached(priority: .userInitiated) {
            AudioConverter.convertToWAV(cafURL, deleteSourceOnSuccess: true)
        }.value
        if let wavURL {
            return AudioRecording(url: wavURL, duration: duration)
        }
        AppLog.warn("AudioRecorder", "conversion WAV impossible — on conserve le CAF \(cafURL.lastPathComponent)")
        return AudioRecording(url: cafURL, duration: duration)
    }
}

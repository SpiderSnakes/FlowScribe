import Foundation

public enum DictationState: Equatable, Sendable { case idle, recording, transcribing }

@MainActor
public final class DictationController {
    public private(set) var state: DictationState = .idle
    public private(set) var lastTranscript: String?

    /// Notifié à la fin d'une dictée (UI : moteur utilisé / repli).
    public var onFinish: ((TranscriptionOutcome) -> Void)?
    /// Contrôle musique optionnel (pause au début, reprise à la fin).
    public var mediaController: MediaController?
    /// Nettoyage IA optionnel appliqué avant le collage.
    public var cleanup: ((String) async -> String)?
    /// Notifié en fin de dictée réussie avec le record à historiser.
    public var onRecord: ((TranscriptionRecord) -> Void)?
    /// Notifié à chaque changement d'état — pilote le HUD quel que soit le déclencheur (hotkey ou bouton).
    public var onStateChange: ((DictationState) -> Void)?
    /// Notifié quand une dictée est annulée (Échap) — l'UI masque le HUD sans toast de résultat.
    public var onCancel: (() -> Void)?

    private let recorder: AudioRecorder
    private var service: TranscriptionService
    private var locale: Locale
    private let output: TextOutput

    private var pressStartedRecording = false
    private var transcriptionTask: Task<Void, Never>?

    public init(recorder: AudioRecorder, service: TranscriptionService, output: TextOutput, locale: Locale) {
        self.recorder = recorder
        self.service = service
        self.output = output
        self.locale = locale
    }

    public func configure(service: TranscriptionService, locale: Locale) {
        self.service = service
        self.locale = locale
    }

    private func setState(_ newState: DictationState) {
        state = newState
        onStateChange?(newState)
    }

    public func pressDown() {
        if state == .idle {
            do {
                try recorder.start()
                setState(.recording)
                pressStartedRecording = true
                mediaController?.pauseForDictation()
            } catch {
                setState(.idle)
            }
        } else {
            pressStartedRecording = false
        }
    }

    public func pressUp(kind: PressKind) async {
        switch kind {
        case .hold:
            await finishRecording()
        case .tap:
            if pressStartedRecording { return } else { await finishRecording() }
        }
    }

    /// Annule la dictée en cours (Échap) : ni transcription, ni collage. Idempotent depuis idle.
    public func cancel() {
        guard state != .idle else { return }
        transcriptionTask?.cancel()
        transcriptionTask = nil
        if state == .recording {
            Task { _ = await recorder.stop() }   // arrête le micro, jette l'audio
        }
        lastTranscript = nil
        setState(.idle)
        mediaController?.resumeAfterDictation()
        onCancel?()
    }

    private func finishRecording() async {
        guard state == .recording else { return }
        let recording = await recorder.stop()
        setState(.transcribing)
        let task = Task { await self.runTranscription(recording: recording) }
        transcriptionTask = task
        await task.value
    }

    private func runTranscription(recording: AudioRecording) async {
        let outcome = await service.transcribe(fileAt: recording.url, locale: locale)
        if Task.isCancelled { return }   // annulée pendant la transcription → on jette
        switch outcome {
        case let .success(text, engineId, _):
            var finalText = text
            if let cleanup { finalText = await cleanup(finalText) }
            if Task.isCancelled { return }
            lastTranscript = finalText
            output.deliver(finalText)
            onRecord?(TranscriptionRecord(
                id: UUID(), date: Date(), text: finalText, engineId: engineId,
                locale: locale.identifier, audioFileName: recording.url.lastPathComponent,
                duration: recording.duration))
        case .failed:
            lastTranscript = nil
        }
        transcriptionTask = nil
        setState(.idle)
        mediaController?.resumeAfterDictation()
        onFinish?(outcome)
    }
}

import Foundation

public enum DictationState: Equatable, Sendable { case idle, recording, transcribing }

@MainActor
public final class DictationController {
    public private(set) var state: DictationState = .idle
    public private(set) var lastTranscript: String?

    private let recorder: AudioRecorder
    private let engine: TranscriptionEngine
    private let output: TextOutput
    private let locale: Locale

    /// True si l'appui en cours a lui-même démarré l'enregistrement (sert au comportement du tap).
    private var pressStartedRecording = false

    public init(recorder: AudioRecorder, engine: TranscriptionEngine, output: TextOutput, locale: Locale) {
        self.recorder = recorder
        self.engine = engine
        self.output = output
        self.locale = locale
    }

    /// Appel sur keyDown du hotkey.
    public func pressDown() {
        if state == .idle {
            do {
                try recorder.start()
                state = .recording
                pressStartedRecording = true
            } catch {
                state = .idle
            }
        } else {
            pressStartedRecording = false
        }
    }

    /// Appel sur keyUp du hotkey, avec le type d'appui classifié.
    public func pressUp(kind: PressKind) async {
        switch kind {
        case .hold:
            // Push-to-talk : on relâche -> on arrête toujours.
            await finishRecording()
        case .tap:
            // Bascule : si ce tap vient de démarrer, on laisse tourner ; sinon il arrête.
            if pressStartedRecording {
                return
            } else {
                await finishRecording()
            }
        }
    }

    private func finishRecording() async {
        guard state == .recording else { return }
        let recording = await recorder.stop()
        state = .transcribing
        do {
            let text = try await engine.transcribeFile(at: recording.url, locale: locale)
            lastTranscript = text
            output.deliver(text)
        } catch {
            lastTranscript = nil
        }
        state = .idle
    }
}

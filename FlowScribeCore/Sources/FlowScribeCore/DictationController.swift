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
    /// Garde-fou pré-enregistrement : renvoie `false` si le moteur sélectionné NE PEUT PAS transcrire
    /// (ex. modèle Apple pas encore prêt). Dans ce cas on N'ENREGISTRE PAS — inutile de faire parler
    /// l'utilisateur pour échouer ensuite. OPTIMISTE : nil ou `true` => on enregistre normalement.
    public var canStart: (@MainActor () -> Bool)?
    /// Notifié quand `canStart` a bloqué le démarrage — l'UI affiche un message clair (et peut relancer
    /// la préparation du modèle).
    public var onStartBlocked: (@MainActor () -> Void)?

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
        if newState != state { AppLog.info("Dictation", "état \(state) → \(newState)") }
        state = newState
        onStateChange?(newState)
    }

    public func pressDown() {
        if state == .idle {
            // Garde-fou : si le moteur ne peut pas transcrire (modèle Apple pas prêt), on ne lance pas
            // l'enregistrement → pas de dictée perdue, message immédiat à la place.
            if let canStart, !canStart() {
                AppLog.warn("Dictation", "démarrage bloqué : moteur de transcription pas prêt")
                onStartBlocked?()
                return
            }
            do {
                try recorder.start()
                setState(.recording)
                pressStartedRecording = true
                mediaController?.pauseForDictation()
            } catch {
                AppLog.error("Dictation", "démarrage de l'enregistrement impossible : \(error)")
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
    /// `async` : on attend l'arrêt réel du micro AVANT de libérer l'état, sinon un nouveau
    /// `start()` immédiat pourrait croiser le `stop()` différé (tap retiré → dictée vide).
    public func cancel() async {
        guard state != .idle else { return }
        AppLog.info("Dictation", "annulation (Échap) depuis l'état \(state)")
        transcriptionTask?.cancel()
        transcriptionTask = nil
        if state == .recording {
            _ = await recorder.stop()   // arrête le micro, jette l'audio — terminé avant .idle
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
        AppLog.info("Dictation", "transcription de \(recording.url.lastPathComponent)")
        let outcome = await service.transcribe(fileAt: recording.url, locale: locale, audioDuration: recording.duration)
        if Task.isCancelled { return }   // annulée pendant la transcription → on jette
        switch outcome {
        case let .success(text, engineId, _):
            var finalText = text
            if let cleanup {
                let before = finalText.count
                finalText = await cleanup(finalText)
                AppLog.info("Dictation", "reformulation \(before)→\(finalText.count) car")
            }
            if Task.isCancelled { return }
            lastTranscript = finalText
            output.deliver(finalText)
            AppLog.info("Dictation", "collage \(finalText.count) car (moteur \(engineId))")
            onRecord?(TranscriptionRecord(
                id: UUID(), date: Date(), text: finalText, engineId: engineId,
                locale: locale.identifier, audioFileName: recording.url.lastPathComponent,
                duration: recording.duration))
        case .failed:
            if Task.isCancelled { return }   // annulée → ne pas créer de faux enregistrement d'échec
            lastTranscript = nil
            // On historise quand même l'échec (audio conservé) pour pouvoir relancer plus tard.
            onRecord?(TranscriptionRecord(
                id: UUID(), date: Date(), text: "", engineId: "",
                locale: locale.identifier, audioFileName: recording.url.lastPathComponent,
                duration: recording.duration, errorMessage: "La transcription a échoué — relance-la quand tu veux."))
        }
        transcriptionTask = nil
        setState(.idle)
        mediaController?.resumeAfterDictation()
        onFinish?(outcome)
    }
}

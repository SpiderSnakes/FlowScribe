import SwiftUI
import FlowScribeCore

@main
struct FlowScribeApp: App {
    @State private var permissions = PermissionsModel()
    @State private var settings = SettingsStore(secrets: KeychainSecretStore())
    @State private var glossary = JSONGlossaryStore(url: URL.applicationSupportDirectory.appending(path: "FlowScribe/glossary.json"))
    @State private var profiles = JSONCorrectionProfileStore(url: URL.applicationSupportDirectory.appending(path: "FlowScribe/corrections.json"))
    @State private var history = HistoryModel(
        store: JSONHistoryStore(url: URL.applicationSupportDirectory.appending(path: "FlowScribe/history.json")),
        recordingsDir: URL.applicationSupportDirectory.appending(path: "FlowScribe/recordings"))
    @State private var modes = ModesModel(
        store: JSONModeStore(url: URL.applicationSupportDirectory.appending(path: "FlowScribe/modes.json")))
    @State private var controller: DictationController?
    @State private var bridge: HotkeyBridge?

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                if settings.hasSeenOnboarding {
                    RootView(settings: settings, permissions: permissions,
                             glossary: glossary, profiles: profiles, history: history, modes: modes,
                             onToggleRecord: { toggleRecord() },
                             onRetranscribe: { r, p, modelId in await retranscribe(r, with: p, modelId: modelId) },
                             onTranscribeFile: { url, p, modelId in await transcribeFile(url, with: p, modelId: modelId) },
                             onActivateMode: { applyMode($0) })
                } else {
                    OnboardingView(permissions: permissions) { settings.hasSeenOnboarding = true }
                }
            }
            .frame(minWidth: 720, minHeight: 480)
            .environment(\.ambiance, Ambiance(palette: BrandPalette(settings.ambiancePalette),
                                              intensity: settings.ambianceIntensity))
            .task { await setup() }
        }
        .windowStyle(.hiddenTitleBar)   // pas de grand bandeau « FlowScribe » ; pastilles superposées
        MenuBarExtra("FlowScribe", systemImage: "mic.fill") {
            MenuBarContent()
        }
    }

    @MainActor
    private func toggleRecord() {
        guard let c = controller else { return }
        c.pressDown()
        Task { await c.pressUp(kind: .tap) }
    }

    /// Relance la transcription d'un enregistrement avec un modèle précis, et met à jour
    /// l'entrée EN PLACE (même id, même audio) — pas de doublon, l'audio reste intact même en cas d'échec.
    @MainActor
    private func retranscribe(_ r: TranscriptionRecord, with provider: EngineProvider, modelId: String) async {
        let url = history.audioURL(r.audioFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let apple = AppleSpeechEngine()
        let primary = provider.makeEngine(apiKey: settings.apiKey(for: provider),
                                          modelId: modelId,
                                          transport: URLSessionTransport()) ?? apple
        let service = TranscriptionService(primary: primary, fallback: apple, postCorrector: PostCorrector(store: profiles))
        let outcome = await service.transcribe(fileAt: url, locale: Locale(identifier: r.locale), audioDuration: r.duration)
        switch outcome {
        case let .success(text, engineId, _):
            history.update(TranscriptionRecord(id: r.id, date: r.date, text: text, engineId: engineId,
                                               locale: r.locale, audioFileName: r.audioFileName, duration: r.duration))
        case .failed:
            history.update(TranscriptionRecord(id: r.id, date: r.date, text: "", engineId: "",
                                               locale: r.locale, audioFileName: r.audioFileName, duration: r.duration,
                                               errorMessage: "La transcription a encore échoué — réessaie."))
        }
    }

    @MainActor
    private func transcribeFile(_ source: URL, with provider: EngineProvider, modelId: String) async -> Bool {
        let id = UUID()
        guard let name = try? history.importAudio(from: source, id: id) else { return false }
        let url = history.audioURL(name)
        let duration = await FileTranscription.duration(of: url)
        let apple = AppleSpeechEngine()
        let primary = provider.makeEngine(apiKey: settings.apiKey(for: provider),
                                          modelId: modelId,
                                          transport: URLSessionTransport()) ?? apple
        let service = TranscriptionService(primary: primary, fallback: apple, postCorrector: PostCorrector(store: profiles))
        let outcome = await service.transcribe(fileAt: url, locale: Locale(identifier: settings.localeIdentifier), audioDuration: duration)
        guard case let .success(text, engineId, _) = outcome else { return false }
        history.add(TranscriptionRecord(id: id, date: Date(), text: text, engineId: engineId,
                                        locale: settings.localeIdentifier, audioFileName: name, duration: duration))
        return true
    }

    /// Active un mode : applique ses valeurs au SettingsStore (qui pilote le pipeline).
    @MainActor
    private func applyMode(_ mode: Mode) {
        settings.applyBatch {   // plusieurs réglages → une seule reconstruction du pipeline
            settings.defaultProvider = mode.provider
            settings.setModel(mode.modelId, for: mode.provider)
            settings.localeIdentifier = mode.localeIdentifier
            settings.musicControlEnabled = mode.pauseMusic
            if let r = mode.reformulation {
                settings.cleanupEnabled = true
                settings.cleanupProvider = r.provider
                settings.cleanupModelId = r.modelId
                settings.cleanupPrompt = r.prompt
            } else {
                settings.cleanupEnabled = false
            }
        }
        modes.setActive(mode.id)
    }

    @MainActor
    private func setup() async {
        permissions.refresh()   // l'onboarding pilote les demandes ; pas d'invite groupée au lancement
        NSApp.setActivationPolicy(settings.runInBackground ? .accessory : .regular)
        guard controller == nil else { return }
        // Seed : un mode « Par défaut » dérivé des réglages courants à la 1re exécution.
        if modes.modes.isEmpty {
            let m = Mode(name: "Par défaut", provider: settings.defaultProvider,
                         modelId: settings.selectedModelId(for: settings.defaultProvider),
                         localeIdentifier: settings.localeIdentifier, pauseMusic: settings.musicControlEnabled,
                         reformulation: nil)
            modes.upsert(m)
            modes.setActive(m.id)
        }
        let dir = URL.applicationSupportDirectory.appending(path: "FlowScribe/recordings")
        let recorder = MicrophoneRecorder(outputDirectory: dir)
        recorder.preferredDeviceUID = settings.selectedMicrophoneUID
        let hud = RecordingHUD()
        hud.style = settings.recordingWindowStyle
        hud.ambiance = Ambiance(palette: BrandPalette(settings.ambiancePalette), intensity: settings.ambianceIntensity)
        recorder.onLevel = { level in
            Task { @MainActor in hud.setLevel(level) }
        }
        let c = DictationController(
            recorder: recorder,
            service: Self.makeService(from: settings, profiles: profiles),
            output: SystemTextOutput(),
            locale: Locale(identifier: settings.localeIdentifier)
        )
        Self.applyOptions(to: c, settings: settings)
        c.onRecord = { [history] r in history.add(r) }
        c.onStateChange = { [hud, settings] s in
            if s != .idle { hud.show(state: s) }
            if settings.soundEffectsEnabled {
                if s == .recording { SoundEffects.playStart() }
                else if s == .transcribing { SoundEffects.playStop() }
            }
        }
        c.onFinish = { [hud] outcome in
            if case .failed = outcome {
                // Pas d'alerte intrusive : l'enregistrement est gardé dans l'historique pour relance.
                hud.showResult("Échec — gardé dans l'historique", isError: true)
            } else {
                hud.showResult(Self.resultMessage(for: outcome))
            }
        }
        c.onCancel = { [hud, settings] in
            hud.hide()
            if settings.soundEffectsEnabled { SoundEffects.playStop() }
        }
        controller = c
        bridge = HotkeyBridge(controller: c)
        history.purge(maxAgeDays: settings.retentionDays)
        settings.onChange = { [weak c, settings, profiles, hud, recorder] in
            guard let c else { return }
            c.configure(service: Self.makeService(from: settings, profiles: profiles),
                        locale: Locale(identifier: settings.localeIdentifier))
            Self.applyOptions(to: c, settings: settings)
            hud.style = settings.recordingWindowStyle
            hud.ambiance = Ambiance(palette: BrandPalette(settings.ambiancePalette), intensity: settings.ambianceIntensity)
            recorder.preferredDeviceUID = settings.selectedMicrophoneUID
        }
    }

    @MainActor
    private static func makeService(from settings: SettingsStore, profiles: CorrectionProfileStore) -> TranscriptionService {
        let transport = URLSessionTransport()
        let apple = AppleSpeechEngine()
        let provider = settings.defaultProvider
        let primary = provider.makeEngine(apiKey: settings.apiKey(for: provider),
                                          modelId: settings.selectedModelId(for: provider),
                                          transport: transport) ?? apple
        return TranscriptionService(primary: primary, fallback: apple, postCorrector: PostCorrector(store: profiles))
    }

    @MainActor
    private static func applyOptions(to c: DictationController, settings: SettingsStore) {
        c.mediaController = MediaController(player: AppleScriptMediaPlayer(), enabled: settings.musicControlEnabled)
        c.cleanup = makeCleanup(settings)
    }

    @MainActor
    private static func makeCleanup(_ settings: SettingsStore) -> ((String) async -> String)? {
        guard settings.cleanupEnabled else { return nil }
        let provider = settings.cleanupProvider
        let key = settings.apiKey(for: provider)
        guard provider.capabilities.contains(.text), !key.isEmpty else { return nil }
        let model = settings.cleanupModelId.isEmpty ? provider.defaultTextModelId : settings.cleanupModelId
        let prompt = settings.cleanupPrompt
        let svc = TextLLMService(provider: provider, model: model, apiKey: key, transport: URLSessionTransport())
        return { (try? await svc.complete(system: prompt, user: $0)) ?? $0 }
    }

    private static func resultMessage(for outcome: TranscriptionOutcome) -> String {
        switch outcome {
        case let .success(_, engineId, usedFallback):
            return usedFallback ? "Repli Apple local" : "via \(engineId)"
        case .failed:
            return "Échec — réessaie"
        }
    }
}

/// Menu de la barre de menus : ouvrir la fenêtre (même en mode arrière-plan) et quitter.
private struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("Ouvrir FlowScribe") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quitter") { NSApplication.shared.terminate(nil) }
    }
}

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
    @State private var controller: DictationController?
    @State private var bridge: HotkeyBridge?

    var body: some Scene {
        WindowGroup("FlowScribe") {
            RootView(settings: settings, permissions: permissions,
                     glossary: glossary, profiles: profiles, history: history,
                     onToggleRecord: { toggleRecord() },
                     onRetranscribe: { r, p in await retranscribe(r, with: p) },
                     onTranscribeFile: { url, p, modelId in await transcribeFile(url, with: p, modelId: modelId) })
                .frame(minWidth: 720, minHeight: 480)
                .task { await setup() }
        }
        .windowStyle(.hiddenTitleBar)   // pas de grand bandeau « FlowScribe » ; pastilles superposées
        MenuBarExtra("FlowScribe", systemImage: "mic.fill") {
            Button("Quitter") { NSApplication.shared.terminate(nil) }
        }
    }

    @MainActor
    private func toggleRecord() {
        guard let c = controller else { return }
        c.pressDown()
        Task { await c.pressUp(kind: .tap) }
    }

    @MainActor
    private func retranscribe(_ r: TranscriptionRecord, with provider: EngineProvider) async {
        let url = history.audioURL(r.audioFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let apple = AppleSpeechEngine()
        let primary = provider.makeEngine(apiKey: settings.apiKey(for: provider),
                                          modelId: settings.selectedModelId(for: provider),
                                          transport: URLSessionTransport()) ?? apple
        let service = TranscriptionService(primary: primary, fallback: apple, postCorrector: PostCorrector(store: profiles))
        let outcome = await service.transcribe(fileAt: url, locale: Locale(identifier: r.locale))
        if case let .success(text, engineId, _) = outcome {
            history.add(TranscriptionRecord(id: UUID(), date: Date(), text: text, engineId: engineId,
                                            locale: r.locale, audioFileName: r.audioFileName, duration: r.duration))
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
        let outcome = await service.transcribe(fileAt: url, locale: Locale(identifier: settings.localeIdentifier))
        guard case let .success(text, engineId, _) = outcome else { return false }
        history.add(TranscriptionRecord(id: id, date: Date(), text: text, engineId: engineId,
                                        locale: settings.localeIdentifier, audioFileName: name, duration: duration))
        return true
    }

    @MainActor
    private func setup() async {
        permissions.refresh()
        await permissions.requestAll()
        guard controller == nil else { return }
        let dir = URL.applicationSupportDirectory.appending(path: "FlowScribe/recordings")
        let recorder = MicrophoneRecorder(outputDirectory: dir)
        let hud = RecordingHUD()
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
        c.onStateChange = { [hud] s in if s != .idle { hud.show(state: s) } }
        c.onFinish = { [hud] outcome in hud.showResult(Self.resultMessage(for: outcome)) }
        c.onCancel = { [hud] in hud.hide() }
        controller = c
        bridge = HotkeyBridge(controller: c)
        history.purge(maxAgeDays: settings.retentionDays)
        settings.onChange = { [weak c, settings, profiles] in
            guard let c else { return }
            c.configure(service: Self.makeService(from: settings, profiles: profiles),
                        locale: Locale(identifier: settings.localeIdentifier))
            Self.applyOptions(to: c, settings: settings)
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
        let transport = URLSessionTransport()
        let mistral = settings.apiKey(for: .mistral)
        if !mistral.isEmpty {
            let svc = AICleanupService(config: .mistral, apiKey: mistral, transport: transport)
            return { (try? await svc.cleanup($0)) ?? $0 }
        }
        let openai = settings.apiKey(for: .openAI)
        if !openai.isEmpty {
            let svc = AICleanupService(config: .openAI, apiKey: openai, transport: transport)
            return { (try? await svc.cleanup($0)) ?? $0 }
        }
        return nil
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

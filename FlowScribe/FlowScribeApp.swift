import SwiftUI
import FlowScribeCore

@main
struct FlowScribeApp: App {
    @State private var permissions = PermissionsModel()
    @State private var settings = SettingsStore(secrets: KeychainSecretStore())
    @State private var glossary = JSONGlossaryStore(url: URL.applicationSupportDirectory.appending(path: "FlowScribe/glossary.json"))
    @State private var profiles = JSONCorrectionProfileStore(url: URL.applicationSupportDirectory.appending(path: "FlowScribe/corrections.json"))
    @State private var controller: DictationController?
    @State private var bridge: HotkeyBridge?

    var body: some Scene {
        WindowGroup("FlowScribe") {
            VStack(spacing: 16) {
                Text("FlowScribe").font(.title2.bold())
                Text("Appuie sur ⌥Espace pour dicter.").foregroundStyle(.secondary)
                if !permissions.allGranted {
                    Divider()
                    PermissionsView(model: permissions)
                    Text("Réglages (⌘,) pour les clés, le moteur, le glossaire et la calibration.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(width: 380)
            .tint(Theme.accent)
            .task { await setup() }
        }
        Settings {
            TabView {
                SettingsView(settings: settings, permissions: permissions)
                    .tabItem { Label("Réglages", systemImage: "gearshape") }
                GlossaryView(glossary: glossary, profiles: profiles)
                    .tabItem { Label("Glossaire", systemImage: "text.book.closed") }
                CalibrationView(glossary: glossary, profiles: profiles, settings: settings)
                    .tabItem { Label("Calibration", systemImage: "waveform") }
            }
        }
        MenuBarExtra("FlowScribe", systemImage: "mic.fill") {
            SettingsLink { Text("Réglages…") }
            Button("Quitter") { NSApplication.shared.terminate(nil) }
        }
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
        controller = c
        bridge = HotkeyBridge(controller: c, hud: hud)
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
        let primary = provider.makeEngine(apiKey: settings.apiKey(for: provider), transport: transport) ?? apple
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
}

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
            Button("Quitter") { NSApplication.shared.terminate(nil) }
        }
    }

    @MainActor
    private func setup() async {
        permissions.refresh()
        await permissions.requestAll()
        guard controller == nil else { return }
        let dir = URL.applicationSupportDirectory.appending(path: "FlowScribe/recordings")
        let c = DictationController(
            recorder: MicrophoneRecorder(outputDirectory: dir),
            service: Self.makeService(from: settings, profiles: profiles),
            output: SystemTextOutput(),
            locale: Locale(identifier: settings.localeIdentifier)
        )
        controller = c
        bridge = HotkeyBridge(controller: c, hud: RecordingHUD())
        settings.onChange = { [weak c, settings, profiles] in
            c?.configure(service: Self.makeService(from: settings, profiles: profiles),
                         locale: Locale(identifier: settings.localeIdentifier))
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
}

import SwiftUI
import FlowScribeCore

@main
struct FlowScribeApp: App {
    @State private var permissions = PermissionsModel()
    @State private var settings = SettingsStore(secrets: KeychainSecretStore())
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
                    Text("Réglages (⌘,) pour les clés et le moteur.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(width: 380)
            .task { await setup() }
        }
        Settings { SettingsView(settings: settings, permissions: permissions) }
        MenuBarExtra("FlowScribe", systemImage: "mic.fill") {
            Button("Réglages…") { NSApp.activate(ignoringOtherApps: true) }
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
            service: Self.makeService(from: settings),
            output: SystemTextOutput(),
            locale: Locale(identifier: settings.localeIdentifier)
        )
        controller = c
        bridge = HotkeyBridge(controller: c, hud: RecordingHUD())
        // Application à chaud : un changement de moteur/clé/langue reconstruit le service.
        settings.onChange = { [weak c, settings] in
            c?.configure(service: Self.makeService(from: settings),
                         locale: Locale(identifier: settings.localeIdentifier))
        }
    }

    @MainActor
    private static func makeService(from settings: SettingsStore) -> TranscriptionService {
        let transport = URLSessionTransport()
        let apple = AppleSpeechEngine()
        let provider = settings.defaultProvider
        let primary = provider.makeEngine(apiKey: settings.apiKey(for: provider), transport: transport) ?? apple
        return TranscriptionService(primary: primary, fallback: apple)
    }
}

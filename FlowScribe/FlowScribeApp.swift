import SwiftUI
import FlowScribeCore

@main
struct FlowScribeApp: App {
    @State private var permissions = PermissionsModel()
    @State private var settings = SettingsStore(secrets: KeychainSecretStore())
    @State private var bridge: HotkeyBridge?

    var body: some Scene {
        WindowGroup("FlowScribe") {
            VStack(spacing: 16) {
                Text("FlowScribe").font(.title2.bold())
                Text("Appuie sur ⌥Espace pour dicter.").foregroundStyle(.secondary)
                if permissions.allGranted {
                    Label("Autorisations OK", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green).font(.caption)
                } else {
                    Divider()
                    PermissionsView(model: permissions)
                }
            }
            .padding(20)
            .frame(width: 380)
            .task { await setup() }
        }
        Settings { SettingsView(settings: settings) }
        MenuBarExtra("FlowScribe", systemImage: "mic.fill") {
            Button("Quitter") { NSApplication.shared.terminate(nil) }
        }
    }

    @MainActor
    private func setup() async {
        permissions.refresh()
        await permissions.requestAll()
        guard bridge == nil else { return }
        let dir = URL.applicationSupportDirectory.appending(path: "FlowScribe/recordings")
        let transport = URLSessionTransport()
        let apple = AppleSpeechEngine()
        let provider = settings.defaultProvider
        let primary = provider.makeEngine(apiKey: settings.apiKey(for: provider), transport: transport) ?? apple
        let service = TranscriptionService(primary: primary, fallback: apple)
        let controller = DictationController(
            recorder: MicrophoneRecorder(outputDirectory: dir),
            service: service,
            output: SystemTextOutput(),
            locale: Locale(identifier: settings.localeIdentifier)
        )
        bridge = HotkeyBridge(controller: controller, hud: RecordingHUD())
    }
}

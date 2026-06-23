import SwiftUI
import FlowScribeCore

@main
struct FlowScribeApp: App {
    @State private var permissions = PermissionsModel()
    @State private var bridge: HotkeyBridge?

    var body: some Scene {
        WindowGroup("FlowScribe") {
            VStack(spacing: 16) {
                Text("FlowScribe").font(.title2.bold())
                Text("Appuie sur ⌥Espace pour dicter.").foregroundStyle(.secondary)
                Divider()
                PermissionsView(model: permissions)
            }
            .padding(20)
            .frame(width: 380)
            .task { await setup() }
        }
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
        let controller = DictationController(
            recorder: MicrophoneRecorder(outputDirectory: dir),
            engine: AppleSpeechEngine(),
            output: SystemTextOutput(),
            locale: Locale(identifier: "fr-FR")
        )
        bridge = HotkeyBridge(controller: controller, hud: RecordingHUD())
    }
}

import SwiftUI
import FlowScribeCore

@main
struct FlowScribeApp: App {
    @State private var bridge: HotkeyBridge?

    var body: some Scene {
        WindowGroup("FlowScribe") {
            VStack(spacing: 12) {
                Text("FlowScribe").font(.title2.bold())
                Text("Appuie sur ⌥Espace pour dicter.").foregroundStyle(.secondary)
            }
            .frame(width: 360, height: 200)
            .task { await setup() }
        }
        MenuBarExtra("FlowScribe", systemImage: "mic.fill") {
            Button("Quitter") { NSApplication.shared.terminate(nil) }
        }
    }

    @MainActor
    private func setup() async {
        guard bridge == nil else { return }
        _ = await Permissions.requestMicrophone()
        _ = await Permissions.requestSpeech()
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

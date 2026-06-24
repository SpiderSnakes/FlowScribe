import SwiftUI
import FlowScribeCore

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let permissions: PermissionsModel

    @State private var micDevices: [AudioInputDevice] = []

    var body: some View {
        Form {
            Section {
                Picker("Périphérique d'entrée", selection: $settings.selectedMicrophoneUID) {
                    Text("Système (par défaut)").tag("")
                    ForEach(micDevices) { Text($0.name).tag($0.id) }
                }
                Picker("Fenêtre d'enregistrement", selection: $settings.recordingWindowStyle) {
                    ForEach(RecordingWindowStyle.allCases) { Text($0.title).tag($0) }
                }
            } header: { Text("Enregistrement") }

            Section {
                Toggle("Repères sonores (début/fin)", isOn: $settings.soundEffectsEnabled)
                Toggle("Lancer FlowScribe au démarrage de session", isOn: $settings.launchAtLogin)
                Toggle("Tourner en arrière-plan (masquer l'icône du Dock)", isOn: $settings.runInBackground)
            } header: { Text("Application") } footer: {
                Text("En arrière-plan, FlowScribe reste accessible par le raccourci clavier et l'icône de la barre de menus (en haut).")
            }

            Section {
                APIKeysPanel(settings: settings)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: { Text("Clés API") }

            Section {
                Picker("Conserver les enregistrements", selection: $settings.retentionDays) {
                    ForEach(RetentionOption.all) { Text($0.title).tag($0.days) }
                }
            } header: { Text("Conservation") }

            Section("Autorisations") {
                permissionRow("Micro", ok: permissions.mic == .granted)
                permissionRow("Reconnaissance vocale", ok: permissions.speech == .granted)
                permissionRow("Accessibilité (collage)", ok: permissions.accessibility)
                HStack {
                    Button("Demander") { Task { await permissions.requestAll() } }
                    if permissions.mic != .granted {
                        Button("Réglages Micro") { Permissions.openMicrophoneSettings() }
                    }
                    if !permissions.accessibility {
                        Button("Réglages Accessibilité") { Permissions.openAccessibilitySettings() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .buttonStyle(.glass)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            permissions.refresh()
            if !RetentionOption.dayValues.contains(settings.retentionDays) { settings.retentionDays = 30 }
        }
        .task {
            micDevices = await Task.detached { CoreAudioDevices.inputDevices() }.value
        }
    }

    private func permissionRow(_ label: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(label)
            Spacer()
        }
    }
}

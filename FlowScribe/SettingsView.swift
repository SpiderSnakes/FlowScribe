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
            } header: { Text("Application") }

            Section {
                APIKeysPanel(settings: settings)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: { Text("Clés API") }

            Section {
                Picker("Conserver les enregistrements", selection: $settings.retentionDays) {
                    Text("Toujours").tag(0)
                    Text("1 jour").tag(1)
                    Text("1 semaine").tag(7)
                    Text("2 semaines").tag(14)
                    Text("1 mois").tag(30)
                    Text("6 mois").tag(180)
                    Text("1 an").tag(365)
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
            micDevices = CoreAudioDevices.inputDevices()
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

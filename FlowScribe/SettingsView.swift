import SwiftUI
import FlowScribeCore

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let permissions: PermissionsModel
    let history: HistoryModel

    @State private var micDevices: [AudioInputDevice] = []
    @State private var confirmDeleteAll = false

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
                Picker("Palette", selection: $settings.ambiancePalette) {
                    ForEach(AmbiancePalette.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Intensité des effets", selection: $settings.ambianceIntensity) {
                    ForEach(AmbianceIntensity.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } header: { Text("Apparence") } footer: {
                Text("La palette colore les effets (aurores, fils, halos). L'intensité règle leur animation ; « Réduire les animations » du système est toujours respecté.")
            }

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
                Button(role: .destructive) { confirmDeleteAll = true } label: {
                    Label("Supprimer tous les enregistrements", systemImage: "trash")
                }
                .disabled(history.records.isEmpty)
            } header: { Text("Conservation") }
            .confirmationDialog("Supprimer toutes les transcriptions et leurs enregistrements audio ?",
                                isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Tout supprimer", role: .destructive) { history.deleteAll() }
                Button("Annuler", role: .cancel) {}
            }

            Section("Autorisations") {
                permissionRow("Micro", ok: permissions.mic == .granted)
                permissionRow("Reconnaissance vocale", ok: permissions.speech == .granted)
                permissionRow("Accessibilité (collage)", ok: permissions.accessibility)
                HStack {
                    if permissions.mic != .granted || permissions.speech != .granted || !permissions.accessibility {
                        Button("Demander") { Task { await permissions.requestAll() } }
                    }
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

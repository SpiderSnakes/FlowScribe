import SwiftUI
import AppKit
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
                Toggle("Mettre la musique en pause pendant la dictée", isOn: $settings.musicControlEnabled)
                Toggle("Couper le son du Mac pendant la dictée", isOn: $settings.muteSystemAudioEnabled)
            } header: { Text("Enregistrement") } footer: {
                Text("Deux options complémentaires. « Mettre la musique en pause » suspend Music/Spotify puis reprend le MÊME morceau là où il s'était arrêté. « Couper le son du Mac » coupe toute la sortie audio (jeu, vidéo, autre app) puis rétablit l'état exact. Tu peux activer l'une, l'autre, ou les deux.")
            }

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
                Toggle("Afficher l'icône dans la barre des menus", isOn: $settings.showMenuBarIcon)
                Toggle("Démarrer masqué (fenêtre invisible au lancement)", isOn: $settings.launchHidden)
                    .disabled(!settings.runInBackground)
            } header: { Text("Application") } footer: {
                Text("Pour une app totalement invisible (façon SuperWhisper) : active « arrière-plan » + « démarrer masqué » et décoche l'icône de la barre des menus. La dictée reste pilotée par le raccourci ⌥Espace ; pour rouvrir les réglages, clique « Ouvrir FlowScribe » dans la barre des menus, ou relance FlowScribe via Spotlight — la fenêtre réapparaît. Fermer la fenêtre ne quitte l'app qu'en mode normal (en arrière-plan, elle continue).")
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

            Section {
                Button {
                    let url = AppLog.fileURL
                    if FileManager.default.fileExists(atPath: url.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } else {
                        NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
                    }
                } label: { Label("Voir les journaux", systemImage: "doc.text.magnifyingglass") }
                Button(role: .destructive) { AppLog.clear() } label: {
                    Label("Vider les journaux", systemImage: "trash")
                }
            } header: { Text("Diagnostics") } footer: {
                Text("Un fichier de journaux (transcriptions, erreurs) à transmettre en cas de souci. Vide-le avant de reproduire un bug pour n'envoyer que l'incident.")
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

            Section {
                HStack {
                    Spacer()
                    Text("FlowScribe \(Self.appVersion)")
                        .font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(GrainientBackground())
        .buttonStyle(.glass)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            permissions.refresh()
            if !RetentionOption.dayValues.contains(settings.retentionDays) { settings.retentionDays = 30 }
        }
        .task {
            micDevices = await Task.detached { CoreAudioDevices.inputDevices() }.value
        }
        // Re-énumère au retour dans l'app : un micro branché/débranché (hot-plug) apparaît/disparaît
        // dans le Picker au lieu de rester figé sur l'énumération initiale.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { micDevices = await Task.detached { CoreAudioDevices.inputDevices() }.value }
        }
    }

    /// Version affichée, lue dans l'Info.plist — MÊMES clés que le panneau « À propos » de macOS,
    /// donc toujours synchronisée avec lui (ex. « 0.3.0 (4) »).
    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func permissionRow(_ label: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
                .accessibilityHidden(true)   // icône décorative : l'état est porté par .accessibilityValue
            Text(label)
            Spacer()
        }
        // Regroupe l'icône + le libellé en un seul élément annoncé « Micro : autorisé / non autorisé ».
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(ok ? "Autorisé" : "Non autorisé")
    }
}

import SwiftUI
import FlowScribeCore

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let permissions: PermissionsModel

    @State private var keyDrafts: [String: String] = [:]
    @State private var results: [String: KeyTestResult] = [:]
    @State private var testing: Set<String> = []
    @State private var micDevices: [AudioInputDevice] = []

    private var cloudProviders: [EngineProvider] {
        EngineProvider.allCases.filter { $0.secretKey != nil }
    }

    var body: some View {
        Form {
            Section("Moteur par défaut") {
                Picker("Moteur", selection: $settings.defaultProvider) {
                    ForEach(EngineProvider.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }
            }

            Section("Clés API (stockées dans le Keychain)") {
                ForEach(cloudProviders, id: \.self) { p in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            SecureField(p.displayName, text: draftBinding(p))
                            statusIcon(for: p)
                            Button("Tester") { test(p) }
                                .disabled(testing.contains(p.secretKey ?? ""))
                        }
                        if p.models.count > 1 {
                            Picker("Modèle", selection: Binding(
                                get: { settings.selectedModelId(for: p) },
                                set: { settings.setModel($0, for: p) })) {
                                ForEach(p.models, id: \.id) { m in Text(m.displayName).tag(m.id) }
                            }
                        }
                        if let msg = message(for: p) {
                            Text(msg).font(.caption).foregroundStyle(resultColor(for: p))
                        }
                    }
                }
                Button("Enregistrer les clés") { saveAllKeys() }
                    .buttonStyle(.glassProminent)
            }

            Section("Langue") {
                TextField("Identifiant de langue (ex. fr-FR)", text: $settings.localeIdentifier)
            }

            Section("Apparence") {
                Picker("Fenêtre d'enregistrement", selection: $settings.recordingWindowStyle) {
                    ForEach(RecordingWindowStyle.allCases) { Text($0.title).tag($0) }
                }
            }

            Section("Micro") {
                Picker("Périphérique d'entrée", selection: $settings.selectedMicrophoneUID) {
                    Text("Système (par défaut)").tag("")
                    ForEach(micDevices) { Text($0.name).tag($0.id) }
                }
            }

            Section("Confort") {
                Toggle("Mettre la musique en pause pendant la dictée", isOn: $settings.musicControlEnabled)
                Toggle("Repères sonores (début/fin d'enregistrement)", isOn: $settings.soundEffectsEnabled)
                Toggle("Lancer FlowScribe au démarrage de session", isOn: $settings.launchAtLogin)
                Toggle("Nettoyage IA du texte (ponctuation, hésitations)", isOn: $settings.cleanupEnabled)
                if settings.cleanupEnabled {
                    Text("Utilise ta clé Mistral (sinon OpenAI). Ajoute un court délai après la dictée.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Rétention de l'historique") {
                Stepper("Conserver \(settings.retentionDays) jour(s) — 0 = illimité",
                        value: $settings.retentionDays, in: 0...365)
            }

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
            for p in cloudProviders { if let k = p.secretKey { keyDrafts[k] = settings.apiKey(for: p) } }
            permissions.refresh()
            micDevices = CoreAudioDevices.inputDevices()
        }
    }

    @ViewBuilder
    private func statusIcon(for p: EngineProvider) -> some View {
        let key = p.secretKey ?? ""
        if testing.contains(key) {
            ProgressView().controlSize(.small)
        } else if let r = results[key] {
            Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(r.ok ? .green : .red)
        }
    }

    private func message(for p: EngineProvider) -> String? {
        guard let key = p.secretKey, let r = results[key] else { return nil }
        if r.ok { return "Clé valide" + (r.status.map { " (HTTP \($0))" } ?? "") }
        let status = r.status.map { "\($0) — " } ?? ""
        return "Échec : \(status)\(r.message ?? "erreur inconnue")"
    }

    private func resultColor(for p: EngineProvider) -> Color {
        guard let key = p.secretKey, let r = results[key] else { return .secondary }
        return r.ok ? .green : .red
    }

    private func permissionRow(_ label: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(label)
            Spacer()
        }
    }

    private func draftBinding(_ p: EngineProvider) -> Binding<String> {
        let key = p.secretKey ?? p.rawValue
        return Binding(get: { keyDrafts[key] ?? "" }, set: { keyDrafts[key] = $0 })
    }

    private func saveAllKeys() {
        for p in cloudProviders {
            if let key = p.secretKey, let draft = keyDrafts[key] { settings.setAPIKey(draft, for: p) }
        }
    }

    private func test(_ p: EngineProvider) {
        guard let config = p.config, let key = p.secretKey else { return }
        let value = keyDrafts[key] ?? settings.apiKey(for: p)
        guard !value.isEmpty else {
            results[key] = KeyTestResult(ok: false, status: nil, message: "Aucune clé saisie")
            return
        }
        testing.insert(key)
        Task {
            let engine = CloudTranscriptionEngine(config: config, apiKey: value, transport: URLSessionTransport())
            let r = await engine.validateKey()
            results[key] = r
            testing.remove(key)
        }
    }
}

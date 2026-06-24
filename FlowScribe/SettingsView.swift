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
                ForEach(cloudProviders, id: \.self) { p in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            SecureField(p.displayName, text: draftBinding(p))
                            statusIcon(for: p)
                            Button("Tester") { test(p) }
                                .disabled(testing.contains(p.secretKey ?? ""))
                        }
                        if let msg = message(for: p) {
                            Text(msg).font(.caption).foregroundStyle(resultColor(for: p))
                        }
                    }
                }
                Button("Enregistrer les clés") { saveAllKeys() }
                    .buttonStyle(.glassProminent)
            } header: { Text("Clés API") } footer: {
                Text("Tes clés restent dans le Trousseau macOS. Le moteur, le modèle et la langue se choisissent par mode (onglet Modes).")
            }

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

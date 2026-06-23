import SwiftUI
import FlowScribeCore

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let permissions: PermissionsModel

    @State private var keyDrafts: [String: String] = [:]
    @State private var validation: [String: Bool] = [:]
    @State private var testing: Set<String> = []

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
                    HStack(spacing: 8) {
                        SecureField(p.displayName, text: draftBinding(p))
                        statusIcon(for: p)
                        Button("Tester") { test(p) }
                            .disabled(testing.contains(p.secretKey ?? ""))
                    }
                }
                Button("Enregistrer les clés") { saveAllKeys() }
            }

            Section("Langue") {
                TextField("Identifiant de langue (ex. fr-FR)", text: $settings.localeIdentifier)
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
        .frame(width: 460, height: 500)
        .onAppear {
            for p in cloudProviders { if let k = p.secretKey { keyDrafts[k] = settings.apiKey(for: p) } }
            permissions.refresh()
        }
    }

    @ViewBuilder
    private func statusIcon(for p: EngineProvider) -> some View {
        let key = p.secretKey ?? ""
        if testing.contains(key) {
            ProgressView().controlSize(.small)
        } else if let ok = validation[key] {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
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
        guard !value.isEmpty else { validation[key] = false; return }
        testing.insert(key)
        Task {
            let engine = CloudTranscriptionEngine(config: config, apiKey: value, transport: URLSessionTransport())
            let ok = await engine.validateKey()
            validation[key] = ok
            testing.remove(key)
        }
    }
}

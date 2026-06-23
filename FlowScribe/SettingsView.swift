import SwiftUI
import FlowScribeCore

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @State private var keyDrafts: [String: String] = [:]

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
                    SecureField(p.displayName, text: draftBinding(p))
                }
                Button("Enregistrer les clés") {
                    for p in cloudProviders {
                        if let key = p.secretKey, let draft = keyDrafts[key] {
                            settings.setAPIKey(draft, for: p)
                        }
                    }
                }
            }
            Section("Langue") {
                TextField("Identifiant de langue (ex. fr-FR)", text: $settings.localeIdentifier)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 380)
        .onAppear {
            for p in cloudProviders {
                if let key = p.secretKey { keyDrafts[key] = settings.apiKey(for: p) }
            }
        }
    }

    private func draftBinding(_ p: EngineProvider) -> Binding<String> {
        let key = p.secretKey ?? p.rawValue
        return Binding(get: { keyDrafts[key] ?? "" }, set: { keyDrafts[key] = $0 })
    }
}

import SwiftUI
import FlowScribeCore

/// Panneau « Vos propres clés » (inspiré de SuperWhisper « Bring your own keys ») :
/// un fournisseur à la fois — Fournisseur → Clé API → Tester / Enregistrer + statut.
struct APIKeysPanel: View {
    let settings: SettingsStore

    private var providers: [EngineProvider] { EngineProvider.allCases.filter { $0.secretKey != nil } }

    @State private var provider: EngineProvider = .openAI
    @State private var keyDraft = ""
    @State private var result: KeyTestResult?
    @State private var testing = false
    @State private var saveResult: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Vos propres clés").font(.system(size: 16, weight: .semibold))
                Text("Une clé par fournisseur (stockée dans le Trousseau). Les badges indiquent ce que chacun sait faire : 🎙️ Oral = transcription · ✍️ Écrit = reformulation/calibration. Apple fonctionne sans clé.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(Theme.hairline)

            field("Fournisseur") {
                HStack {
                    Picker("", selection: $provider) {
                        ForEach(providers, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                    Spacer()
                    capabilityBadges
                }
            }

            field("Clé API") {
                SecureField("collez votre clé ici…", text: $keyDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }

            if let msg = message {
                Text(msg).font(.caption).foregroundStyle(result?.ok == true ? .green : .orange)
            } else if saveResult == true {
                Text("Clé enregistrée dans le Trousseau.").font(.caption).foregroundStyle(.secondary)
            } else if saveResult == false {
                Text("Échec de l'enregistrement dans le Trousseau.").font(.caption).foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                statusIcon
                Spacer()
                Button("Tester") { test() }
                    .buttonStyle(.glass)
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty || testing || provider.config == nil)
                Button("Enregistrer") { save() }
                    .buttonStyle(.glassProminent)
                    .disabled(testing)
            }
        }
        .padding(18)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .onAppear(perform: load)
        .onChange(of: provider) { _, _ in load() }
    }

    private var capabilityBadges: some View {
        HStack(spacing: 6) {
            if provider.capabilities.contains(.transcription) { badge("Oral", "mic.fill") }
            if provider.capabilities.contains(.text) { badge("Écrit", "text.bubble.fill") }
        }
    }

    private func badge(_ label: String, _ icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(.caption2)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Theme.accent.opacity(0.15), in: Capsule())
            .foregroundStyle(Theme.accent)
    }

    @ViewBuilder
    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.callout).foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder private var statusIcon: some View {
        if testing {
            ProgressView().controlSize(.small)
        } else if let r = result {
            Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(r.ok ? .green : .red)
        }
    }

    private var message: String? {
        guard let r = result else { return nil }
        if r.ok { return "Clé valide" + (r.status.map { " (HTTP \($0))" } ?? "") }
        let status = r.status.map { "\($0) — " } ?? ""
        return "Échec : \(status)\(r.message ?? "erreur inconnue")"
    }

    private func load() {
        keyDraft = settings.apiKey(for: provider)
        result = nil
        saveResult = nil
    }

    private func save() {
        saveResult = settings.setAPIKey(keyDraft, for: provider)
    }

    private func test() {
        guard let config = provider.config else { return }
        let value = keyDraft
        result = nil; saveResult = nil; testing = true
        Task {
            let engine = CloudTranscriptionEngine(config: config, apiKey: value, transport: URLSessionTransport())
            result = await engine.validateKey()
            testing = false
        }
    }
}

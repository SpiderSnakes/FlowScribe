import SwiftUI
import FlowScribeCore

/// « Vos propres clés » — refonte : la liste de TOUS les fournisseurs, d'un coup d'œil on voit
/// lesquels sont configurés (badge « Clé active ») et ce que chacun sait faire (Oral / Écrit).
/// On déplie une ligne pour saisir / tester / enregistrer / retirer la clé. Tout reste dans le Trousseau.
struct APIKeysPanel: View {
    let settings: SettingsStore

    private var providers: [EngineProvider] { EngineProvider.allCases.filter { $0.secretKey != nil } }

    @State private var editing: EngineProvider?
    @State private var keyDraft = ""
    @State private var result: KeyTestResult?
    @State private var testing = false
    @State private var saveResult: Bool?
    /// Cache « une clé est-elle enregistrée ? » (évite de relire le Trousseau à chaque rendu).
    @State private var keySet: [EngineProvider: Bool] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Vos propres clés").font(.system(size: 16, weight: .semibold))
                Text("Une clé par fournisseur, stockée dans le Trousseau. 🎙️ Oral = transcription · ✍️ Écrit = reformulation et calibration. Apple fonctionne sans clé.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 8) {
                ForEach(providers, id: \.self) { row($0) }
            }
        }
        .padding(18)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .onAppear(perform: refreshFlags)
    }

    private func row(_ p: EngineProvider) -> some View {
        let isEditing = editing == p
        return VStack(spacing: 0) {
            Button { toggle(p) } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(p.displayName).font(.system(size: 14, weight: .medium))
                        capabilityBadges(p)
                    }
                    Spacer()
                    statusPill(p)
                    Image(systemName: isEditing ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isEditing {
                editor(p).padding([.horizontal, .bottom], 12)
            }
        }
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .borderGlow(active: isEditing, cornerRadius: 10)
    }

    @ViewBuilder
    private func editor(_ p: EngineProvider) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("collez votre clé \(p.displayName)…", text: $keyDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))

            if let msg = message {
                Text(msg).font(.caption).foregroundStyle(result?.ok == true ? .green : .orange)
            } else if saveResult == true {
                Text("Clé enregistrée dans le Trousseau.").font(.caption).foregroundStyle(.green)
            } else if saveResult == false {
                Text("Échec de l'enregistrement dans le Trousseau.").font(.caption).foregroundStyle(.orange)
            } else if p.config == nil {
                Text("Fournisseur écrit uniquement : pas de test de transcription.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                if testing {
                    ProgressView().controlSize(.small)
                } else if let r = result {
                    Image(systemName: r.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(r.ok ? .green : .red)
                }
                Spacer()
                if p.config != nil {
                    Button("Tester") { test(p) }
                        .buttonStyle(.glass)
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty || testing)
                }
                if keySet[p] == true {
                    Button("Retirer", role: .destructive) { remove(p) }
                        .buttonStyle(.glass)
                        .disabled(testing)
                }
                Button("Enregistrer") { save(p) }
                    .buttonStyle(.glassProminent)
                    .disabled(testing || keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func capabilityBadges(_ p: EngineProvider) -> some View {
        HStack(spacing: 6) {
            if p.capabilities.contains(.transcription) { badge("Oral", "mic.fill") }
            if p.capabilities.contains(.text) { badge("Écrit", "text.bubble.fill") }
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
    private func statusPill(_ p: EngineProvider) -> some View {
        if keySet[p] == true {
            Label("Clé active", systemImage: "checkmark.seal.fill")
                .font(.caption2).foregroundStyle(.green)
        } else {
            Text("Aucune clé").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var message: String? {
        guard let r = result else { return nil }
        if r.ok { return "Clé valide" + (r.status.map { " (HTTP \($0))" } ?? "") }
        let status = r.status.map { "\($0) — " } ?? ""
        return "Échec : \(status)\(r.message ?? "erreur inconnue")"
    }

    private func toggle(_ p: EngineProvider) {
        if editing == p { editing = nil; return }
        editing = p
        keyDraft = settings.apiKey(for: p)   // toujours rechargée depuis le Trousseau (jamais d'état périmé)
        result = nil
        saveResult = nil
        refreshFlags()
    }

    private func save(_ p: EngineProvider) {
        saveResult = settings.setAPIKey(keyDraft, for: p)
        result = nil
        refreshFlags()
    }

    private func remove(_ p: EngineProvider) {
        _ = settings.setAPIKey("", for: p)
        keyDraft = ""
        result = nil
        saveResult = nil
        refreshFlags()
    }

    private func test(_ p: EngineProvider) {
        guard let config = p.config else { return }
        let value = keyDraft
        result = nil; saveResult = nil; testing = true
        Task {
            let engine = CloudTranscriptionEngine(config: config, apiKey: value, transport: URLSessionTransport())
            result = await engine.validateKey()
            testing = false
        }
    }

    private func refreshFlags() {
        for p in providers { keySet[p] = !settings.apiKey(for: p).isEmpty }
    }
}

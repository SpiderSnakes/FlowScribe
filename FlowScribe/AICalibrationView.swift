import SwiftUI
import FlowScribeCore

/// Calibration assistée par IA : un modèle ÉCRIT lit les transcriptions et propose des règles GLOBALES.
/// Le choix du modèle est limité aux fournisseurs/modèles écrits ; on pré-sélectionne un fournisseur
/// déjà configuré, mais tu peux le changer.
struct AICalibrationView: View {
    let settings: SettingsStore
    let profiles: CorrectionProfileStore
    let history: HistoryModel
    @Environment(\.dismiss) private var dismiss

    @State private var provider: EngineProvider = .openAI
    @State private var modelId = EngineProvider.openAI.defaultTextModelId
    @State private var running = false
    @State private var ran = false
    @State private var proposals: [CorrectionProposal] = []
    @State private var accepted: Set<String> = []

    private var key: String { settings.apiKey(for: provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Calibration par IA").font(.system(size: 18, weight: .semibold))
            Text("Une IA écrite lit tes dernières transcriptions et propose des corrections (surtout les noms propres mal transcrits). Tu choisis lesquelles garder — elles deviennent des règles globales.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            // Choix du modèle ÉCRIT uniquement (fournisseurs avec capacité texte + leurs modèles écrits).
            HStack {
                Picker("Modèle écrit", selection: $provider) {
                    ForEach(EngineProvider.textProviders, id: \.self) { Text($0.displayName).tag($0) }
                }
                .onChange(of: provider) { _, p in
                    if !p.textModels.contains(where: { $0.id == modelId }) { modelId = p.defaultTextModelId }
                }
                Picker("", selection: $modelId) {
                    ForEach(provider.textModels, id: \.id) { Text($0.displayName).tag($0.id) }
                }.labelsHidden()
            }

            if key.isEmpty {
                Label("Ajoute ta clé \(provider.displayName) dans Réglages → Clés API.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }

            Button(action: run) {
                if running { HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Analyse…") } }
                else { Label("Analyser mes transcriptions", systemImage: "sparkles") }
            }
            .buttonStyle(.glassProminent)
            .disabled(running || key.isEmpty || history.records.isEmpty)

            Divider()

            if !proposals.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(proposals) { p in
                            Toggle(isOn: binding(p)) {
                                HStack {
                                    Text("« \(p.heard) » → ").foregroundStyle(.secondary) + Text(p.corrected).bold()
                                    Spacer()
                                    Text("\(p.occurrences)×").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            } else if ran && !running {
                Text("Aucune correction proposée 🎉").font(.callout).foregroundStyle(.secondary)
                Spacer()
            } else {
                Spacer()
            }

            HStack {
                Spacer()
                Button("Fermer") { dismiss() }.buttonStyle(.glass)
                Button("Ajouter les corrections") { addSelected() }
                    .buttonStyle(.glassProminent)
                    .disabled(accepted.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560, height: 540)
        .background(VisualEffectBackground(material: .sidebar).ignoresSafeArea())
        .onAppear {
            // Pré-sélection d'un fournisseur écrit déjà configuré (modifiable).
            if let (p, m) = resolveProvider() {
                provider = p; modelId = m
            } else if settings.cleanupProvider.capabilities.contains(.text) {
                provider = settings.cleanupProvider; modelId = provider.defaultTextModelId
            }
        }
    }

    /// Premier fournisseur écrit avec une clé : celui de la reformulation en priorité, sinon le premier configuré.
    private func resolveProvider() -> (EngineProvider, String)? {
        let cleanup = settings.cleanupProvider
        if cleanup.capabilities.contains(.text), !settings.apiKey(for: cleanup).isEmpty {
            let m = settings.cleanupModelId.isEmpty ? cleanup.defaultTextModelId : settings.cleanupModelId
            return (cleanup, m)
        }
        for p in EngineProvider.textProviders where !settings.apiKey(for: p).isEmpty {
            return (p, p.defaultTextModelId)
        }
        return nil
    }

    private func binding(_ p: CorrectionProposal) -> Binding<Bool> {
        Binding(get: { accepted.contains(p.heard) },
                set: { if $0 { accepted.insert(p.heard) } else { accepted.remove(p.heard) } })
    }

    private func run() {
        running = true; ran = false; proposals = []; accepted = []
        let texts = Array(history.records.prefix(50).map(\.text))
        let p = provider
        let m = modelId.isEmpty ? provider.defaultTextModelId : modelId
        let k = key
        Task {
            let result = await AICalibration.propose(transcriptions: texts, provider: p, model: m,
                                                     apiKey: k, transport: URLSessionTransport())
            proposals = result
            accepted = Set(result.map(\.heard))
            running = false; ran = true
        }
    }

    private func addSelected() {
        for p in proposals where accepted.contains(p.heard) {
            profiles.add(CorrectionRule(heard: p.heard, replacement: p.corrected), for: CorrectionScope.global)
        }
        dismiss()
    }
}

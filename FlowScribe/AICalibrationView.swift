import SwiftUI
import FlowScribeCore

/// Calibration assistée par IA : un modèle écrit lit les transcriptions et propose des règles GLOBALES.
/// Système unifié : pas de choix de modèle — on prend automatiquement un fournisseur écrit configuré.
struct AICalibrationView: View {
    let settings: SettingsStore
    let profiles: CorrectionProfileStore
    let history: HistoryModel
    @Environment(\.dismiss) private var dismiss

    @State private var provider: EngineProvider?
    @State private var modelId = ""
    @State private var running = false
    @State private var ran = false
    @State private var proposals: [CorrectionProposal] = []
    @State private var accepted: Set<String> = []

    private var key: String { provider.map { settings.apiKey(for: $0) } ?? "" }
    private var modelName: String {
        provider?.textModels.first(where: { $0.id == modelId })?.displayName ?? provider?.displayName ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Calibration par IA").font(.system(size: 18, weight: .semibold))
            Text("Une IA écrite lit tes dernières transcriptions et propose des corrections (surtout les noms propres mal transcrits). Tu choisis lesquelles garder — elles deviennent des règles globales.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if provider != nil {
                HStack(spacing: 8) {
                    Image(systemName: "cpu").foregroundStyle(.secondary)
                    Text("Modèle utilisé :").foregroundStyle(.secondary)
                    Text(modelName).fontWeight(.medium)
                }
                .font(.callout)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            } else {
                Label("Aucune clé IA écrite configurée. Ajoute une clé (OpenAI, Anthropic, Mistral ou Google) dans Réglages → Clés API.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }

            Button(action: run) {
                if running { HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Analyse…") } }
                else { Label("Analyser mes transcriptions", systemImage: "sparkles") }
            }
            .buttonStyle(.glassProminent)
            .disabled(running || provider == nil || history.records.isEmpty)

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
            if let (p, m) = resolveProvider() { provider = p; modelId = m }
        }
    }

    /// Choisit automatiquement un fournisseur écrit : (1) celui de la reformulation s'il a une clé,
    /// (2) sinon le premier fournisseur écrit avec une clé, (3) sinon aucun.
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
        guard let p = provider else { return }
        running = true; ran = false; proposals = []; accepted = []
        let texts = Array(history.records.prefix(50).map(\.text))
        let m = modelId.isEmpty ? p.defaultTextModelId : modelId
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

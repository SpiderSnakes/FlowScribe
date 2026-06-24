import SwiftUI
import AppKit
import FlowScribeCore

struct TranscriptionDetailView: View {
    let record: TranscriptionRecord
    let history: HistoryModel
    let profiles: CorrectionProfileStore
    let onRetranscribe: (TranscriptionRecord, EngineProvider, String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.ambiance) private var ambiance
    @State private var playback = AudioPlayback()
    @State private var ruleHeard = ""
    @State private var ruleReplacement = ""
    @State private var ruleAdded = false
    @State private var working = false

    /// Version courante de l'enregistrement (l'historique est @Observable) : après une re-transcription
    /// en place, la vue se rafraîchit toute seule (texte/statut à jour) sans rouvrir la feuille.
    private var current: TranscriptionRecord {
        history.records.first { $0.id == record.id } ?? record
    }
    private var audioURL: URL { history.audioURL(current.audioFileName) }
    private var hasAudio: Bool { history.audioExists(current.audioFileName) }
    private var wordCount: Int { current.text.split { $0 == " " || $0 == "\n" }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            ScrollView {
                if current.text.isEmpty {
                    Text(current.failed ? "Pas encore de transcription — relance-la ci-dessous."
                                        : "Transcription vide.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                } else {
                    Text(current.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .frame(maxHeight: .infinity)

            if !current.text.isEmpty { createRule }

            HStack {
                if hasAudio {
                    Button { playback.toggle(url: audioURL) } label: {
                        Label(playback.isPlaying ? "Arrêter" : "Écouter",
                              systemImage: playback.isPlaying ? "stop.fill" : "play.fill")
                    }.buttonStyle(.glass)
                }
                if !current.text.isEmpty {
                    Button { copy(current.text) } label: { Label("Copier", systemImage: "doc.on.doc") }
                        .buttonStyle(.glass)
                }
                Menu {
                    ForEach(EngineProvider.transcriptionProviders, id: \.self) { p in
                        Section(p.displayName) {
                            ForEach(p.models, id: \.id) { m in
                                Button(m.displayName) { retranscribe(p, m.id) }
                            }
                        }
                    }
                } label: {
                    Label(working ? "Transcription…" : (current.failed ? "Transcrire" : "Re-transcrire"),
                          systemImage: "arrow.clockwise")
                }
                .disabled(!hasAudio || working)
                .fixedSize()
                Spacer()
                Button(role: .destructive) {
                    playback.stop(); history.delete(current); dismiss()
                } label: { Label("Supprimer", systemImage: "trash") }
                    .buttonStyle(.glass)
                Button("Fermer") { playback.stop(); dismiss() }.buttonStyle(.glassProminent)
            }
        }
        .padding(20)
        .frame(width: 580, height: 560)
        .background(VisualEffectBackground(material: .sidebar).ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(RecordFormat.dateLabel(current.date)).font(.system(size: 16, weight: .semibold))
            if current.failed {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(ambiance.palette.warm)
                    Text(current.errorMessage ?? "La transcription a échoué.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(ambiance.palette.warm.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            } else {
                HStack(spacing: 10) {
                    if !current.engineId.isEmpty { Label(current.engineId, systemImage: "cpu") }
                    if let d = current.duration { Label(RecordFormat.duration(d), systemImage: "clock") }
                    Label("\(wordCount) mots", systemImage: "text.word.spacing")
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var createRule: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Créer une règle de correction").font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                TextField("entendu (ex. Doc Ploy)", text: $ruleHeard).textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                TextField("corrigé (ex. Dokploy)", text: $ruleReplacement).textFieldStyle(.roundedBorder)
                Button("Créer") { addRule() }
                    .buttonStyle(.glass)
                    .disabled(ruleHeard.trimmingCharacters(in: .whitespaces).isEmpty
                              || ruleReplacement.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if ruleAdded {
                Text("Règle ajoutée (globale). Visible dans Corrections.").font(.caption).foregroundStyle(Theme.sky)
            } else {
                Text("Astuce : copie le mot mal transcrit depuis le texte ci-dessus.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func addRule() {
        let heard = ruleHeard.trimmingCharacters(in: .whitespaces)
        let replacement = ruleReplacement.trimmingCharacters(in: .whitespaces)
        guard !heard.isEmpty, !replacement.isEmpty else { return }
        profiles.add(CorrectionRule(heard: heard, replacement: replacement), for: CorrectionScope.global)
        ruleHeard = ""; ruleReplacement = ""; ruleAdded = true
    }

    private func retranscribe(_ p: EngineProvider, _ modelId: String) {
        working = true
        Task { await onRetranscribe(current, p, modelId); working = false }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

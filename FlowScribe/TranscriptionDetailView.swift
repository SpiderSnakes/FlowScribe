import SwiftUI
import AppKit
import FlowScribeCore

struct TranscriptionDetailView: View {
    let record: TranscriptionRecord
    let history: HistoryModel
    let profiles: CorrectionProfileStore
    let onRetranscribe: (TranscriptionRecord, EngineProvider) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var playback = AudioPlayback()
    @State private var ruleHeard = ""
    @State private var ruleReplacement = ""
    @State private var ruleAdded = false
    @State private var working = false

    private var audioURL: URL { history.audioURL(record.audioFileName) }
    private var hasAudio: Bool { history.audioExists(record.audioFileName) }
    private var wordCount: Int { record.text.split { $0 == " " || $0 == "\n" }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            ScrollView {
                Text(record.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .frame(maxHeight: .infinity)

            createRule

            HStack {
                if hasAudio {
                    Button { playback.toggle(url: audioURL) } label: {
                        Label(playback.isPlaying ? "Arrêter" : "Écouter",
                              systemImage: playback.isPlaying ? "stop.fill" : "play.fill")
                    }.buttonStyle(.glass)
                }
                Button { copy(record.text) } label: { Label("Copier", systemImage: "doc.on.doc") }
                    .buttonStyle(.glass)
                Menu {
                    ForEach(EngineProvider.transcriptionProviders, id: \.self) { p in
                        Button(p.displayName) { retranscribe(p) }
                    }
                } label: { Label("Re-transcrire", systemImage: "arrow.clockwise") }
                .disabled(!hasAudio || working)
                .fixedSize()
                Spacer()
                Button(role: .destructive) {
                    playback.stop(); history.delete(record); dismiss()
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
        VStack(alignment: .leading, spacing: 4) {
            Text(RecordFormat.dateLabel(record.date)).font(.system(size: 16, weight: .semibold))
            HStack(spacing: 10) {
                Label(record.engineId, systemImage: "cpu")
                if let d = record.duration { Label(RecordFormat.duration(d), systemImage: "clock") }
                Label("\(wordCount) mots", systemImage: "text.word.spacing")
            }
            .font(.caption).foregroundStyle(.secondary)
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

    private func retranscribe(_ p: EngineProvider) {
        working = true
        Task { await onRetranscribe(record, p); working = false }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

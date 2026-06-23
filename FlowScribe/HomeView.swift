import SwiftUI
import FlowScribeCore

struct HomeView: View {
    let settings: SettingsStore
    let permissions: PermissionsModel
    let history: HistoryModel
    let onToggleRecord: () -> Void
    let onRetranscribe: (TranscriptionRecord, EngineProvider) async -> Void

    @State private var query = ""

    private var filtered: [TranscriptionRecord] {
        query.isEmpty ? history.records
            : history.records.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 12) {
            if !permissions.allGranted {
                PermissionsView(model: permissions)
                Divider()
            }
            HStack(spacing: 12) {
                Button(action: onToggleRecord) {
                    Image(systemName: "mic.fill").font(.system(size: 18)).frame(width: 44, height: 44)
                }
                .buttonStyle(.glassProminent).clipShape(Circle())
                Text("Moteur : \(settings.defaultProvider.displayName)")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            TextField("Rechercher dans l'historique…", text: $query)
                .textFieldStyle(.roundedBorder)
            if filtered.isEmpty {
                Spacer()
                Text(history.records.isEmpty ? "Aucune transcription pour l'instant." : "Aucun résultat.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(filtered) { row($0) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ r: TranscriptionRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(r.text).lineLimit(3)
            HStack(spacing: 8) {
                Text(r.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                Text("· \(r.engineId)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copier") { copy(r.text) }.buttonStyle(.borderless)
                Menu("Re-transcrire") {
                    ForEach(EngineProvider.allCases, id: \.self) { p in
                        Button(p.displayName) { Task { await onRetranscribe(r, p) } }
                    }
                }
                .disabled(!history.audioExists(r.audioFileName))
                .fixedSize()
                Button(role: .destructive) { history.delete(r) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

import SwiftUI
import FlowScribeCore

struct HomeView: View {
    let settings: SettingsStore
    let permissions: PermissionsModel
    let history: HistoryModel
    let profiles: CorrectionProfileStore
    let modes: ModesModel
    let onToggleRecord: () -> Void
    let onRetranscribe: (TranscriptionRecord, EngineProvider) async -> Void
    let onActivateMode: (Mode) -> Void

    @State private var query = ""
    @State private var selected: TranscriptionRecord?

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
                Menu {
                    ForEach(modes.modes) { m in
                        Button { onActivateMode(m) } label: {
                            Label(m.name, systemImage: m.id == modes.activeModeId ? "checkmark" : "square.stack.3d.up")
                        }
                    }
                } label: {
                    Label("Mode : \(modes.activeMode?.name ?? "—")", systemImage: "square.stack.3d.up")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
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
                    .scrollContentBackground(.hidden)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $selected) { r in
            TranscriptionDetailView(record: r, history: history, profiles: profiles, onRetranscribe: onRetranscribe)
        }
    }

    private func row(_ r: TranscriptionRecord) -> some View {
        Button { selected = r } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(r.text).lineLimit(2).foregroundStyle(.primary)
                HStack(spacing: 8) {
                    Text(RecordFormat.dateLabel(r.date))
                    Text("· \(r.engineId)")
                    if let d = r.duration { Text("· \(RecordFormat.duration(d))") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}

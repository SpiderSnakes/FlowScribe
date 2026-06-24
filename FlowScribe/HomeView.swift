import SwiftUI
import FlowScribeCore

struct HomeView: View {
    let settings: SettingsStore
    let permissions: PermissionsModel
    let history: HistoryModel
    let profiles: CorrectionProfileStore
    let modes: ModesModel
    let onToggleRecord: () -> Void
    let onRetranscribe: (TranscriptionRecord, EngineProvider, String) async -> Void
    let onActivateMode: (Mode) -> Void

    @State private var query = ""
    @State private var selected: TranscriptionRecord?

    private var filtered: [TranscriptionRecord] {
        query.isEmpty ? history.records
            : history.records.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !permissions.allGranted {
                PermissionsView(model: permissions)
            }

            HStack(alignment: .center, spacing: 12) {
                Text("Historique").font(.system(size: 22, weight: .bold))
                Spacer()
                modeChip
                Button(action: onToggleRecord) {
                    Label("Dicter", systemImage: "mic.fill")
                }
                .buttonStyle(.glassProminent)
                .help("Dicter (⌥Espace)")
            }

            if !history.records.isEmpty {
                TextField("Rechercher…", text: $query)
                    .textFieldStyle(.roundedBorder)
            }

            if filtered.isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { card($0) }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $selected) { r in
            TranscriptionDetailView(record: r, history: history, profiles: profiles, onRetranscribe: onRetranscribe)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: history.records.isEmpty ? "waveform" : "magnifyingglass")
                .font(.system(size: 30)).foregroundStyle(.secondary)
            Text(history.records.isEmpty
                 ? "Aucune transcription. Appuie sur ⌥Espace pour dicter."
                 : "Aucun résultat.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var modeChip: some View {
        Menu {
            ForEach(modes.modes) { m in
                Button { onActivateMode(m) } label: {
                    Label(m.name, systemImage: m.id == modes.activeModeId ? "checkmark" : "square.stack.3d.up")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.stack.3d.up").font(.system(size: 11))
                Text(modes.activeMode?.name ?? "—").font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    /// Carte d'historique : aérée, un aperçu lisible + une ligne de méta discrète ; les échecs
    /// portent un repère orange et restent ouvrables pour relancer la transcription.
    private func card(_ r: TranscriptionRecord) -> some View {
        Button { selected = r } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(r.failed ? "Échec de transcription" : (r.text.isEmpty ? "—" : r.text))
                        .lineLimit(2)
                        .font(.system(size: 14))
                        .foregroundStyle(r.failed ? .secondary : .primary)
                    HStack(spacing: 8) {
                        Text(RecordFormat.dateLabel(r.date))
                        if !r.engineId.isEmpty { metaChip(r.engineId) }
                        if let d = r.duration { Text(RecordFormat.duration(d)) }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: r.failed ? "exclamationmark.triangle.fill" : "chevron.right")
                    .font(.caption)
                    .foregroundStyle(r.failed ? Color.orange : Color.secondary.opacity(0.6))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.primary.opacity(0.07), in: Capsule())
    }
}

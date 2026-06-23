import SwiftUI
import FlowScribeCore

struct RootView: View {
    let settings: SettingsStore
    let permissions: PermissionsModel
    let glossary: GlossaryStore
    let profiles: CorrectionProfileStore
    let history: HistoryModel
    let onToggleRecord: () -> Void
    let onRetranscribe: (TranscriptionRecord, EngineProvider) async -> Void
    let onTranscribeFile: (URL, EngineProvider, String) async -> Bool

    @State private var section: AppSection = .accueil

    var body: some View {
        NavigationSplitView {
            SidebarView(section: $section)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            ZStack {
                VisualEffectBackground(material: .sidebar).ignoresSafeArea()
                detailContent
            }
        }
        .tint(Theme.accent)
    }

    @ViewBuilder private var detailContent: some View {
        switch section {
        case .accueil:
            HomeView(settings: settings, permissions: permissions, history: history,
                     onToggleRecord: onToggleRecord, onRetranscribe: onRetranscribe)
        case .fichiers:
            FilesView(settings: settings, onTranscribeFile: onTranscribeFile)
        case .vocabulaire:
            VocabularyView(glossary: glossary, profiles: profiles, settings: settings)
        case .reglages:
            SettingsView(settings: settings, permissions: permissions)
        }
    }
}

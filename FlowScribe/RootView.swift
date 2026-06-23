import SwiftUI
import FlowScribeCore

struct RootView: View {
    let settings: SettingsStore
    let permissions: PermissionsModel
    let glossary: GlossaryStore
    let profiles: CorrectionProfileStore
    let onToggleRecord: () -> Void

    @State private var section: AppSection = .accueil

    var body: some View {
        NavigationSplitView {
            SidebarView(section: $section)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            switch section {
            case .accueil:
                HomeView(settings: settings, permissions: permissions, onToggleRecord: onToggleRecord)
            case .vocabulaire:
                VocabularyView(glossary: glossary, profiles: profiles, settings: settings)
            case .reglages:
                SettingsView(settings: settings, permissions: permissions)
            }
        }
        .tint(Theme.accent)
    }
}

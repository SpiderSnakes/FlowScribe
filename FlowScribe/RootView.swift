import SwiftUI
import FlowScribeCore

struct RootView: View {
    let settings: SettingsStore
    let permissions: PermissionsModel
    let glossary: GlossaryStore
    let profiles: CorrectionProfileStore
    let history: HistoryModel
    let modes: ModesModel
    let onToggleRecord: () -> Void
    let onRetranscribe: (TranscriptionRecord, EngineProvider) async -> Void
    let onTranscribeFile: (URL, EngineProvider, String) async -> Bool
    let onActivateMode: (Mode) -> Void

    @State private var section: AppSection = .accueil
    @State private var micName = "Micro système"
    @State private var micDevices: [AudioInputDevice] = []

    var body: some View {
        NavigationSplitView {
            SidebarView(section: $section)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            ZStack {
                VisualEffectBackground(material: .sidebar).ignoresSafeArea()
                detailContent
            }
            .safeAreaInset(edge: .top) {
                HStack {
                    Spacer()
                    Menu {
                        Button { settings.selectedMicrophoneUID = "" } label: {
                            Label("Système (par défaut)", systemImage: settings.selectedMicrophoneUID.isEmpty ? "checkmark" : "mic")
                        }
                        ForEach(micDevices) { d in
                            Button { settings.selectedMicrophoneUID = d.id } label: {
                                Label(d.name, systemImage: settings.selectedMicrophoneUID == d.id ? "checkmark" : "mic")
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "mic.fill").font(.system(size: 10))
                            Text(micName).font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
            .onAppear {
                micDevices = CoreAudioDevices.inputDevices()
                micName = settings.selectedMicrophoneUID.isEmpty ? "Micro système"
                    : (CoreAudioDevices.name(forUID: settings.selectedMicrophoneUID) ?? "Micro")
            }
            .onChange(of: settings.selectedMicrophoneUID) { _, uid in
                micName = uid.isEmpty ? "Micro système" : (CoreAudioDevices.name(forUID: uid) ?? "Micro")
            }
        }
        .tint(Theme.accent)
    }

    @ViewBuilder private var detailContent: some View {
        switch section {
        case .accueil:
            HomeView(settings: settings, permissions: permissions, history: history,
                     modes: modes, onToggleRecord: onToggleRecord, onRetranscribe: onRetranscribe,
                     onActivateMode: onActivateMode)
        case .modes:
            ModesView(modes: modes, settings: settings, onActivate: onActivateMode)
        case .fichiers:
            FilesView(settings: settings, onTranscribeFile: onTranscribeFile)
        case .vocabulaire:
            VocabularyView(glossary: glossary, profiles: profiles, settings: settings)
        case .reglages:
            SettingsView(settings: settings, permissions: permissions)
        }
    }
}

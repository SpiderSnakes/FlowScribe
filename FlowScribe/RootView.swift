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
    @State private var micDevices: [AudioInputDevice] = []

    /// Nom du micro actif, dérivé de la liste déjà chargée (pas de ré-énumération CoreAudio).
    private var micName: String {
        settings.selectedMicrophoneUID.isEmpty ? "Micro système"
            : (micDevices.first { $0.id == settings.selectedMicrophoneUID }?.name ?? "Micro")
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(section: $section)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            ZStack {
                VisualEffectBackground(material: .sidebar).ignoresSafeArea()
                detailContent
            }
            .safeAreaInset(edge: .top, spacing: 0) {
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
                .padding(.horizontal, 14).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(.bar)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [Color.black.opacity(0.10), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 10).offset(y: 10).allowsHitTesting(false)
                }
            }
            .task {
                // énumération CoreAudio hors du thread principal (AudioInputDevice est Sendable)
                micDevices = await Task.detached { CoreAudioDevices.inputDevices() }.value
            }
        }
        .tint(Theme.accent)
    }

    @ViewBuilder private var detailContent: some View {
        switch section {
        case .accueil:
            HomeView(settings: settings, permissions: permissions, history: history,
                     profiles: profiles, modes: modes, onToggleRecord: onToggleRecord,
                     onRetranscribe: onRetranscribe, onActivateMode: onActivateMode)
        case .modes:
            ModesView(modes: modes, settings: settings, onActivate: onActivateMode)
        case .fichiers:
            FilesView(settings: settings, onTranscribeFile: onTranscribeFile)
        case .corrections:
            CorrectionsView(profiles: profiles)
        case .calibration:
            CalibrationSectionView(glossary: glossary, profiles: profiles, settings: settings)
        case .reglages:
            SettingsView(settings: settings, permissions: permissions, history: history)
        }
    }
}

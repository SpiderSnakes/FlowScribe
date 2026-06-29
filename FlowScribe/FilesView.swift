import SwiftUI
import UniformTypeIdentifiers
import FlowScribeCore

struct FilesView: View {
    let settings: SettingsStore
    /// Transcrit le fichier avec le provider + modèle choisis ; renvoie true si succès.
    let onTranscribeFile: (URL, EngineProvider, String) async -> Bool

    @State private var selected: URL?
    @State private var provider: EngineProvider = .appleLocal
    @State private var modelId: String = ""
    @State private var isWorking = false
    @State private var dropTargeted = false
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Transcrire un fichier")
                .font(.system(size: 20, weight: .semibold))

            dropZone

            HStack(spacing: 12) {
                modelMenu
                Spacer()
                Button("Choisir un fichier…", action: pickFile)
                    .buttonStyle(.glass)
            }

            if let message {
                Label(message, systemImage: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(isError ? .orange : Theme.sky)
                    .font(.system(size: 13))
            }

            Spacer()

            HStack {
                Spacer()
                Button(action: transcribe) {
                    if isWorking {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Transcription…") }
                    } else {
                        Label("Transcrire", systemImage: "waveform.badge.mic")
                    }
                }
                .buttonStyle(.glassProminent)
                .disabled(selected == nil || isWorking)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            // Idempotent : on n'amorce le défaut qu'au premier affichage, sinon le choix d'un
            // modèle non-défaut serait silencieusement perdu en revenant sur l'onglet Fichiers.
            if modelId.isEmpty {
                provider = settings.defaultProvider
                modelId = settings.selectedModelId(for: provider)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            Image(systemName: selected == nil ? "square.and.arrow.down" : "waveform")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.sky)
            if let selected {
                Text(selected.lastPathComponent)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1).truncationMode(.middle)
                Button("Retirer") { self.selected = nil; message = nil }
                    .buttonStyle(.borderless).font(.caption)
            } else {
                Text("Glissez un fichier audio ici").font(.system(size: 14, weight: .medium))
                Text("ou utilisez « Choisir un fichier… »").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 150)
        .background(Theme.glassTint, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(dropTargeted ? Theme.sky : Theme.hairline)
        )
        .animation(.easeInOut(duration: 0.15), value: dropTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            // Filtre sur les types audio, cohérent avec le NSOpenPanel (un PDF/image déposé était
            // accepté puis échouait seulement après une tentative de transcription complète).
            guard let url = urls.first(where: { $0.isFileURL }),
                  let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .audio) else {
                message = "Fichier non audio."; isError = true
                return false
            }
            selected = url; message = nil
            return true
        } isTargeted: { dropTargeted = $0 }
        // Accessible à VoiceOver : la zone est décrite comme une cible de dépôt avec le fichier choisi.
        // (Le bouton « Choisir un fichier… » reste le chemin pleinement accessible au clavier.)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Zone de dépôt de fichier audio")
        .accessibilityValue(selected?.lastPathComponent ?? "Aucun fichier sélectionné")
    }

    private var modelMenu: some View {
        Menu {
            ForEach(EngineProvider.transcriptionProviders, id: \.self) { p in
                Menu(p.displayName) {
                    ForEach(p.models, id: \.id) { m in
                        Button(m.displayName) { provider = p; modelId = m.id }
                    }
                }
            }
        } label: {
            let model = provider.models.first { $0.id == modelId }
            Label("\(provider.displayName) · \(model?.displayName ?? "")", systemImage: "cpu")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .mpeg4Audio, .mp3, .wav, .aiff]
        if panel.runModal() == .OK, let url = panel.url {
            selected = url; message = nil
        }
    }

    private func transcribe() {
        guard let url = selected else { return }
        isWorking = true; message = nil
        Task {
            let ok = await onTranscribeFile(url, provider, modelId)
            isWorking = false
            isError = !ok
            message = ok ? "Transcrit — voir l'Accueil." : "Échec — réessaie ou changez de modèle."
            if ok { selected = nil }
        }
    }
}

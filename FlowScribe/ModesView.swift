import SwiftUI
import FlowScribeCore

struct ModesView: View {
    let modes: ModesModel
    let settings: SettingsStore
    let onActivate: (Mode) -> Void

    @State private var editing: Mode?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Modes").font(.system(size: 20, weight: .semibold))
                    Spacer()
                    Button { editing = newMode() } label: { Label("Nouveau mode", systemImage: "plus") }
                        .buttonStyle(.glass)
                }
                Text("Chaque mode regroupe un moteur, une langue, la pause musique et un style de nettoyage. Active-en un pour reconfigurer la dictée d'un geste.")
                    .font(.callout).foregroundStyle(.secondary)

                ForEach(modes.modes) { mode in
                    row(mode)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $editing) { mode in
            ModeEditor(mode: mode, settings: settings) { saved in
                modes.upsert(saved)
                editing = nil
            } onCancel: { editing = nil }
        }
    }

    private func row(_ mode: Mode) -> some View {
        let isActive = modes.activeModeId == mode.id
        return HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Theme.accent : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.name).font(.system(size: 14, weight: .semibold))
                Text("\(mode.provider.displayName) · \(modelName(mode)) · \(mode.localeIdentifier)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !isActive {
                Button("Activer") { onActivate(mode) }.buttonStyle(.glass)
            } else {
                Text("Actif").font(.caption.bold()).foregroundStyle(Theme.accent)
            }
            Button { editing = mode } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
            Button(role: .destructive) { modes.delete(mode) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .disabled(modes.modes.count <= 1)   // garder au moins un mode
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    private func modelName(_ mode: Mode) -> String {
        mode.provider.models.first { $0.id == mode.modelId }?.displayName ?? mode.modelId
    }

    private func newMode() -> Mode {
        Mode(name: "Nouveau mode", provider: settings.defaultProvider,
             modelId: settings.selectedModelId(for: settings.defaultProvider),
             localeIdentifier: settings.localeIdentifier, pauseMusic: settings.musicControlEnabled,
             reformulation: nil)
    }
}

private struct ModeEditor: View {
    @State var mode: Mode
    let settings: SettingsStore
    let onSave: (Mode) -> Void
    let onCancel: () -> Void

    @State private var reformEnabled: Bool
    @State private var reformProvider: EngineProvider
    @State private var reformModelId: String
    @State private var reformPrompt: String

    init(mode: Mode, settings: SettingsStore, onSave: @escaping (Mode) -> Void, onCancel: @escaping () -> Void) {
        _mode = State(initialValue: mode)
        self.settings = settings
        self.onSave = onSave
        self.onCancel = onCancel
        let r = mode.reformulation
        _reformEnabled = State(initialValue: r != nil)
        _reformProvider = State(initialValue: r?.provider ?? .openAI)
        _reformModelId = State(initialValue: r?.modelId ?? EngineProvider.openAI.defaultTextModelId)
        _reformPrompt = State(initialValue: r?.prompt ?? SettingsStore.defaultCleanupPrompt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                Section("Mode") {
                    TextField("Nom", text: $mode.name)
                    Picker("Moteur", selection: $mode.provider) {
                        ForEach(EngineProvider.transcriptionProviders, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .onChange(of: mode.provider) { _, p in
                        if !p.models.contains(where: { $0.id == mode.modelId }) { mode.modelId = p.defaultModelId }
                    }
                    Picker("Modèle", selection: $mode.modelId) {
                        ForEach(mode.provider.models, id: \.id) { Text($0.displayName).tag($0.id) }
                    }
                    Picker("Langue", selection: $mode.localeIdentifier) {
                        ForEach(AppLocales.all, id: \.id) { Text($0.name).tag($0.id) }
                    }
                    Toggle("Mettre la musique en pause", isOn: $mode.pauseMusic)
                }
                Section("Reformulation (2ᵉ passe écrite)") {
                    Toggle("Reformuler la transcription avec une IA écrite", isOn: $reformEnabled)
                    if reformEnabled {
                        Picker("Fournisseur", selection: $reformProvider) {
                            ForEach(EngineProvider.textProviders, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        .onChange(of: reformProvider) { _, p in
                            if !p.textModels.contains(where: { $0.id == reformModelId }) { reformModelId = p.defaultTextModelId }
                        }
                        Picker("Modèle", selection: $reformModelId) {
                            ForEach(reformProvider.textModels, id: \.id) { Text($0.displayName).tag($0.id) }
                        }
                        TextEditor(text: $reformPrompt)
                            .frame(minHeight: 80)
                            .font(.callout)
                        Text("Décris le style voulu (e-mail, notes, code, ton…). Nécessite la clé du fournisseur.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Spacer()
                Button("Annuler", action: onCancel).buttonStyle(.glass)
                Button("Enregistrer") {
                    mode.reformulation = reformEnabled
                        ? Reformulation(provider: reformProvider, modelId: reformModelId, prompt: reformPrompt)
                        : nil
                    onSave(mode)
                }
                .buttonStyle(.glassProminent)
                .disabled(mode.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(16)
        }
        .frame(width: 460, height: 470)
        .background(VisualEffectBackground(material: .sidebar).ignoresSafeArea())
    }
}

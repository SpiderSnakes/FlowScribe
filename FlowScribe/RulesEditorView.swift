import SwiftUI
import FlowScribeCore

/// Règle de correction en cours d'édition (id stable pour SwiftUI).
private struct EditableRule: Identifiable, Equatable {
    let id = UUID()
    var heard: String
    var replacement: String
    var enabled: Bool
}

/// Éditeur des règles de correction — toutes GLOBALES (appliquées à tous les moteurs).
struct RulesEditorView: View {
    let profiles: CorrectionProfileStore

    @State private var editing: [EditableRule] = []
    @State private var loaded = false
    @State private var newHeard = ""
    @State private var newReplacement = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                TextField("entendu", text: $newHeard).textFieldStyle(.roundedBorder).frame(maxWidth: 150)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                TextField("corrigé", text: $newReplacement).textFieldStyle(.roundedBorder).frame(maxWidth: 150)
                Button("Ajouter", action: addRule)
                    .buttonStyle(.glass)
                    .disabled(newHeard.trimmingCharacters(in: .whitespaces).isEmpty
                              || newReplacement.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if editing.isEmpty {
                Text("Aucune règle. Ajoute-en une, ou lance une calibration.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            ForEach($editing) { $rule in
                RuleRow(rule: $rule) { delete(rule.id) }
            }
        }
        .onAppear(perform: load)
        .onChange(of: editing) { _, _ in if loaded { commit() } }
    }

    private func load() {
        guard !loaded else { return }
        editing = profiles.rules(for: CorrectionScope.global).map {
            EditableRule(heard: $0.heard, replacement: $0.replacement, enabled: $0.enabled)
        }
        loaded = true
    }

    private func addRule() {
        editing.append(EditableRule(heard: newHeard.trimmingCharacters(in: .whitespaces),
                                    replacement: newReplacement.trimmingCharacters(in: .whitespaces),
                                    enabled: true))
        newHeard = ""; newReplacement = ""
    }

    private func delete(_ id: UUID) { editing.removeAll { $0.id == id } }

    private func commit() {
        let rules = editing
            .filter { !$0.heard.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { CorrectionRule(heard: $0.heard, replacement: $0.replacement, enabled: $0.enabled) }
        profiles.setRules(rules, for: CorrectionScope.global)
    }
}

private struct RuleRow: View {
    @Binding var rule: EditableRule
    let onDelete: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $rule.enabled).labelsHidden().toggleStyle(.switch).controlSize(.mini)
            TextField("entendu", text: $rule.heard).textFieldStyle(.roundedBorder)
            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
            TextField("corrigé", text: $rule.replacement).textFieldStyle(.roundedBorder)
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless)
        }
        .opacity(rule.enabled ? 1 : 0.5)
    }
}

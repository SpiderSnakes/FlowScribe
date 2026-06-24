import SwiftUI
import FlowScribeCore

/// Règle de correction en cours d'édition (id stable pour SwiftUI).
private struct EditableRule: Identifiable, Equatable {
    let id = UUID()
    var scope: String
    var heard: String
    var replacement: String
    var enabled: Bool
}

/// Éditeur réel des règles de correction : activables, globales ou par moteur, éditables.
struct RulesEditorView: View {
    let profiles: CorrectionProfileStore

    @State private var editing: [EditableRule] = []
    @State private var loaded = false
    @State private var newHeard = ""
    @State private var newReplacement = ""
    @State private var newScope = CorrectionScope.global

    private func engineId(_ p: EngineProvider) -> String { p.config?.id ?? "apple.local" }
    private var scopes: [(key: String, label: String)] {
        [(CorrectionScope.global, "Toutes (global)")] + EngineProvider.allCases.map { (engineId($0), $0.displayName) }
    }
    private func label(for key: String) -> String { scopes.first { $0.key == key }?.label ?? key }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Ajout manuel
            HStack(spacing: 8) {
                TextField("entendu", text: $newHeard).textFieldStyle(.roundedBorder).frame(maxWidth: 130)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                TextField("corrigé", text: $newReplacement).textFieldStyle(.roundedBorder).frame(maxWidth: 130)
                Picker("", selection: $newScope) {
                    ForEach(scopes, id: \.key) { Text($0.label).tag($0.key) }
                }.labelsHidden().fixedSize()
                Button("Ajouter", action: addRule)
                    .buttonStyle(.glass)
                    .disabled(newHeard.trimmingCharacters(in: .whitespaces).isEmpty || newReplacement.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if editing.isEmpty {
                Text("Aucune règle. Ajoute-en une, ou lance une calibration.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            // Groupées par portée
            ForEach(scopes, id: \.key) { scope in
                let hasRules = editing.contains { $0.scope == scope.key }
                if hasRules {
                    Text(scope.label).font(.subheadline.bold()).foregroundStyle(.secondary)
                    ForEach($editing) { $rule in
                        if rule.scope == scope.key {
                            RuleRow(rule: $rule) { delete(rule.id) }
                        }
                    }
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: editing) { _, _ in if loaded { commit() } }
    }

    private func load() {
        guard !loaded else { return }
        var all: [EditableRule] = []
        for scope in scopes {
            for r in profiles.rules(for: scope.key) {
                all.append(EditableRule(scope: scope.key, heard: r.heard, replacement: r.replacement, enabled: r.enabled))
            }
        }
        editing = all
        loaded = true
    }

    private func addRule() {
        editing.append(EditableRule(scope: newScope,
                                    heard: newHeard.trimmingCharacters(in: .whitespaces),
                                    replacement: newReplacement.trimmingCharacters(in: .whitespaces),
                                    enabled: true))
        newHeard = ""; newReplacement = ""
    }

    private func delete(_ id: UUID) { editing.removeAll { $0.id == id } }

    /// Réécrit chaque portée depuis l'état local (les lignes vides sont ignorées).
    private func commit() {
        let grouped = Dictionary(grouping: editing, by: \.scope)
        for scope in scopes {
            let rules = (grouped[scope.key] ?? [])
                .filter { !$0.heard.trimmingCharacters(in: .whitespaces).isEmpty }
                .map { CorrectionRule(heard: $0.heard, replacement: $0.replacement, enabled: $0.enabled) }
            profiles.setRules(rules, for: scope.key)
        }
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

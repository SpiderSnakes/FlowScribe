import SwiftUI
import FlowScribeCore

struct GlossaryView: View {
    let glossary: GlossaryStore
    let profiles: CorrectionProfileStore

    @State private var terms: [String] = []
    @State private var newTerm: String = ""

    var body: some View {
        Form {
            Section("Termes du glossaire") {
                HStack {
                    TextField("Nouveau terme (ex. Dokploy)", text: $newTerm)
                        .onSubmit(addTerm)
                    Button("Ajouter", action: addTerm)
                        .buttonStyle(.glass)
                        .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if terms.isEmpty {
                    Text("Aucun terme. Ajoute tes mots techniques (Dokploy, SwiftUI…).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(terms, id: \.self) { t in
                    HStack {
                        Text(t)
                        Spacer()
                        Button(role: .destructive) { remove(t) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                    }
                }
            }

            Section("Corrections apprises (par moteur)") {
                let anyRules = EngineProvider.allCases.contains { !profiles.rules(for: engineId($0)).isEmpty }
                if !anyRules {
                    Text("Lance une calibration pour apprendre des corrections.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(EngineProvider.allCases, id: \.self) { p in
                    let rules = profiles.rules(for: engineId(p))
                    if !rules.isEmpty {
                        Text(p.displayName).font(.headline)
                        ForEach(rules, id: \.heard) { r in
                            Text("« \(r.heard) » → \(r.replacement)").font(.caption)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { terms = glossary.terms }
    }

    private func addTerm() {
        glossary.add(newTerm)
        newTerm = ""
        terms = glossary.terms
    }
    private func remove(_ t: String) {
        glossary.remove(t)
        terms = glossary.terms
    }
    private func engineId(_ p: EngineProvider) -> String { p.config?.id ?? "apple.local" }
}

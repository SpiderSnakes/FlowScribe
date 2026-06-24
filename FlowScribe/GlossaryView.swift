import SwiftUI
import FlowScribeCore

/// Éditeur des termes du glossaire (biais keyterms + base de la phrase de calibration).
struct GlossaryView: View {
    let glossary: GlossaryStore

    @State private var terms: [String] = []
    @State private var newTerm: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Nouveau terme (ex. Dokploy)", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
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
}

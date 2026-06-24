import SwiftUI
import FlowScribeCore

struct VocabularyView: View {
    let glossary: GlossaryStore
    let profiles: CorrectionProfileStore
    let settings: SettingsStore
    @State private var showCalibration = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                block(title: "Glossaire",
                      subtitle: "Tes mots techniques et noms propres (Dokploy, SwiftUI…). Ils guident la reconnaissance et servent de base à la calibration.") {
                    GlossaryView(glossary: glossary)
                }

                block(title: "Règles de correction",
                      subtitle: "Remplace automatiquement ce qui est mal entendu (« doc ploy » → Dokploy). Globales ou propres à un moteur, activables une par une.") {
                    RulesEditorView(profiles: profiles)
                }

                block(title: "Calibration",
                      subtitle: "Lis une phrase à voix haute : FlowScribe compare et apprend les corrections propres à ton moteur.") {
                    Button("Calibrer un moteur") { showCalibration = true }
                        .buttonStyle(.glassProminent)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showCalibration) {
            CalibrationView(glossary: glossary, profiles: profiles, settings: settings)
        }
    }

    @ViewBuilder
    private func block<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 18, weight: .semibold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
    }
}

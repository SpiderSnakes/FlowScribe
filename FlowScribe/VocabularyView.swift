import SwiftUI
import FlowScribeCore

/// Menu « Corrections » : les règles entendu → corrigé (déterministes), sans calibration.
struct CorrectionsView: View {
    let profiles: CorrectionProfileStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Règles de correction").font(.system(size: 20, weight: .semibold))
                Text("Remplace automatiquement ce qui est mal transcrit (« doc ploy » → Dokploy). Règles globales ou propres à un moteur, activables une par une.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                RulesEditorView(profiles: profiles)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Menu « Calibration » : apprentissage automatique des corrections par lecture d'une phrase,
/// avec le glossaire (qui fournit les termes de la phrase) juste en dessous.
struct CalibrationSectionView: View {
    let glossary: GlossaryStore
    let profiles: CorrectionProfileStore
    let settings: SettingsStore
    @State private var showCalibration = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Calibration").font(.system(size: 20, weight: .semibold))
                    Text("Lis une phrase à voix haute : FlowScribe la compare à la référence et apprend les corrections propres à ton moteur.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Démarrer une calibration") { showCalibration = true }
                        .buttonStyle(.glassProminent)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Glossaire").font(.system(size: 16, weight: .semibold))
                    Text("Tes mots techniques et noms propres (Dokploy, SwiftUI…). Ils servent à construire la phrase de calibration.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    GlossaryView(glossary: glossary)
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
}

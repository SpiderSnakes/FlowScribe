import SwiftUI
import FlowScribeCore

struct VocabularyView: View {
    let glossary: GlossaryStore
    let profiles: CorrectionProfileStore
    let settings: SettingsStore
    @State private var showCalibration = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                GlossaryView(glossary: glossary)
                Divider()
                RulesEditorView(profiles: profiles)
                Divider()
                HStack {
                    Button("Calibrer un moteur") { showCalibration = true }
                        .buttonStyle(.glass)
                    Text("Lis une phrase à voix haute pour apprendre des corrections automatiquement.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showCalibration) {
            CalibrationView(glossary: glossary, profiles: profiles, settings: settings)
        }
    }
}

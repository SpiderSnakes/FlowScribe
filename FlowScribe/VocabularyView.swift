import SwiftUI
import FlowScribeCore

struct VocabularyView: View {
    let glossary: GlossaryStore
    let profiles: CorrectionProfileStore
    let settings: SettingsStore
    @State private var showCalibration = false

    var body: some View {
        VStack(spacing: 0) {
            GlossaryView(glossary: glossary, profiles: profiles)
            Divider()
            Button("Calibrer un moteur") { showCalibration = true }
                .buttonStyle(.glass)
                .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showCalibration) {
            CalibrationView(glossary: glossary, profiles: profiles, settings: settings)
        }
    }
}

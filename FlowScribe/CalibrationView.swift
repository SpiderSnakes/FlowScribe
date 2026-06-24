import SwiftUI
import FlowScribeCore

@MainActor
struct CalibrationView: View {
    let glossary: GlossaryStore
    let profiles: CorrectionProfileStore
    let settings: SettingsStore

    enum Phase: Equatable { case idle, recording, transcribing, review, error(String) }

    @State private var phase: Phase = .idle
    @State private var proposed: [CorrectionRule] = []
    @State private var accepted: Set<String> = []
    @State private var recorder = MicrophoneRecorder(outputDirectory: URL.temporaryDirectory.appending(path: "FlowScribeCalibration"))

    private var provider: EngineProvider { settings.defaultProvider }
    private var engineId: String { provider.engineId }

    private var reference: String {
        let terms = glossary.terms
        guard !terms.isEmpty else { return "Ajoute d'abord des termes dans l'onglet Glossaire." }
        return "Phrase de calibration : " + terms.map { "j'utilise \($0)" }.joined(separator: ", ") + "."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Calibration — \(provider.displayName)").font(.title3.bold())
            Text("Lis la phrase à voix haute ; on apprend les corrections propres à ce moteur.")
                .font(.caption).foregroundStyle(.secondary)

            Text(reference)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .glassEffect(.regular, in: .rect(cornerRadius: 10))

            controls

            if phase == .review {
                Divider()
                Text("Corrections proposées").font(.headline)
                if proposed.isEmpty {
                    Text("Aucune erreur détectée sur tes termes 🎉").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(proposed, id: \.heard) { rule in
                    Toggle(isOn: binding(for: rule)) {
                        Text("« \(rule.heard) » → \(rule.replacement)")
                    }
                }
                if !proposed.isEmpty {
                    Button("Enregistrer les corrections") { saveAccepted() }
                        .buttonStyle(.glassProminent)
                }
            }
            if case let .error(msg) = phase {
                Text(msg).font(.caption).foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(20)
        .frame(width: 460, height: 470)
    }

    @ViewBuilder private var controls: some View {
        switch phase {
        case .idle, .review, .error:
            Button(phase == .idle ? "Démarrer la lecture" : "Recommencer") { start() }
                .buttonStyle(.glassProminent)
                .disabled(glossary.terms.isEmpty)
        case .recording:
            HStack {
                Button("Arrêter et analyser") { stop() }.buttonStyle(.glassProminent)
                Label("Enregistrement…", systemImage: "mic.fill").foregroundStyle(.red)
            }
        case .transcribing:
            HStack { ProgressView().controlSize(.small); Text("Transcription…") }
        }
    }

    private func binding(for rule: CorrectionRule) -> Binding<Bool> {
        Binding(get: { accepted.contains(rule.heard) },
                set: { if $0 { accepted.insert(rule.heard) } else { accepted.remove(rule.heard) } })
    }

    private func start() {
        proposed = []; accepted = []
        do { try recorder.start(); phase = .recording }
        catch { phase = .error("Micro indisponible : \(error.localizedDescription)") }
    }

    private func stop() {
        phase = .transcribing
        Task {
            let recording = await recorder.stop()
            let transport = URLSessionTransport()
            guard let engine = provider.makeEngine(apiKey: settings.apiKey(for: provider), transport: transport) else {
                phase = .error("Clé manquante pour \(provider.displayName).")
                return
            }
            do {
                let text = try await engine.transcribeFile(at: recording.url, locale: Locale(identifier: settings.localeIdentifier))
                proposed = CalibrationService.proposeRules(reference: reference, hypothesis: text, glossary: glossary.terms)
                accepted = Set(proposed.map { $0.heard })
                phase = .review
            } catch {
                phase = .error("Transcription échouée : \(error.localizedDescription)")
            }
        }
    }

    private func saveAccepted() {
        for rule in proposed where accepted.contains(rule.heard) {
            profiles.add(rule, for: engineId)
        }
        phase = .idle
        proposed = []; accepted = []
    }
}

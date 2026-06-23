import SwiftUI

@MainActor
@Observable
final class PermissionsModel {
    var mic: PermissionState = .notDetermined
    var speech: PermissionState = .notDetermined
    var accessibility: Bool = false

    func refresh() {
        mic = Permissions.microphoneState()
        speech = Permissions.speechState()
        accessibility = Permissions.accessibilityTrusted()
    }

    /// Demande toutes les autorisations, séquentiellement, puis rafraîchit le statut.
    func requestAll() async {
        await Permissions.requestMicrophone()
        await Permissions.requestSpeech()
        if !Permissions.accessibilityTrusted() { Permissions.promptAccessibility() }
        refresh()
    }

    // Demandes individuelles (pilotées par l'onboarding, une étape à la fois).
    func requestMicrophone() async { await Permissions.requestMicrophone(); refresh() }
    func requestSpeech() async { await Permissions.requestSpeech(); refresh() }
    func requestAccessibility() { Permissions.promptAccessibility(); refresh() }

    var allGranted: Bool { mic == .granted && speech == .granted && accessibility }
}

private struct PermissionRow: View {
    let label: String
    let ok: Bool
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(label)
            Spacer()
        }
    }
}

struct PermissionsView: View {
    let model: PermissionsModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Autorisations").font(.headline)
            PermissionRow(label: "Micro", ok: model.mic == .granted)
            PermissionRow(label: "Reconnaissance vocale", ok: model.speech == .granted)
            PermissionRow(label: "Accessibilité (collage)", ok: model.accessibility)
            Button("Demander les autorisations") { Task { await model.requestAll() } }
                .buttonStyle(.glassProminent)
                .padding(.top, 4)
            HStack {
                if model.mic != .granted {
                    Button("Réglages Micro") { Permissions.openMicrophoneSettings() }
                }
                if !model.accessibility {
                    Button("Réglages Accessibilité") { Permissions.openAccessibilitySettings() }
                }
            }
            .buttonStyle(.glass)
            if model.mic == .denied {
                Text("Micro refusé : active FlowScribe dans Réglages → Micro, puis relance.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !model.accessibility {
                Text("Après avoir activé l'Accessibilité, relance FlowScribe.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { model.refresh() }
    }
}

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
            HStack {
                Button("Demander les autorisations") { Task { await model.requestAll() } }
                Button("Ouvrir Réglages") { Permissions.openAccessibilitySettings() }
            }
            .padding(.top, 4)
            if !model.accessibility {
                Text("Après avoir activé l'Accessibilité dans les Réglages, relance FlowScribe.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { model.refresh() }
    }
}

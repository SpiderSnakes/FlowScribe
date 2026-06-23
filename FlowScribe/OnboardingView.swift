import SwiftUI
import AppKit

/// Accueil première ouverture : demande les permissions une par une, barre de
/// progression qui avance. Inspiré de SuperWhisper (cf. docs/design-references).
struct OnboardingView: View {
    let permissions: PermissionsModel
    var onDone: () -> Void

    private var grantedCount: Int {
        [permissions.mic == .granted, permissions.speech == .granted, permissions.accessibility]
            .filter { $0 }.count
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            card
                .frame(width: 420)
                .padding(24)
                .background(Theme.glassTint, in: RoundedRectangle(cornerRadius: 20))
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.hairline, lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 30, y: 12)
                .animation(.snappy(duration: 0.25), value: grantedCount)
        }
        .onAppear { permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            ProgressBar(progress: Double(grantedCount) / 3.0)

            VStack(alignment: .leading, spacing: 6) {
                Text("Configurons les autorisations")
                    .font(.system(size: 22, weight: .bold))
                Text("Tout reste en local — la confidentialité d'abord.")
                    .font(.callout).foregroundStyle(Theme.sky)
            }

            VStack(spacing: 14) {
                row(icon: "mic.fill", title: "Micro",
                    desc: "Capter l'audio à transcrire. Utilisé seulement pendant la dictée.",
                    granted: permissions.mic == .granted, locked: false,
                    action: { Task { await permissions.requestMicrophone() } })
                row(icon: "waveform", title: "Reconnaissance vocale",
                    desc: "Requise pour la transcription Apple, sur l'appareil.",
                    granted: permissions.speech == .granted, locked: permissions.mic != .granted,
                    action: { Task { await permissions.requestSpeech() } })
                row(icon: "accessibility", title: "Accessibilité",
                    desc: "Coller le texte dans tes apps (Cmd+V). Utilisée au besoin.",
                    granted: permissions.accessibility, locked: permissions.speech != .granted,
                    action: { permissions.requestAccessibility() })
            }

            if !permissions.accessibility && permissions.speech == .granted {
                Button("Ouvrir les Réglages d'Accessibilité") { Permissions.openAccessibilitySettings() }
                    .buttonStyle(.glass).font(.caption)
            }

            VStack(spacing: 8) {
                Button(action: onDone) {
                    Text("Commencer à utiliser FlowScribe").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!permissions.allGranted)

                if !permissions.allGranted {
                    Button("Ignorer pour l'instant", action: onDone)
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(icon: String, title: String, desc: String,
                     granted: Bool, locked: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(granted ? Theme.sky : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(desc).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.system(size: 18))
            } else {
                Button("Autoriser", action: action).buttonStyle(.glass).disabled(locked)
            }
        }
        .opacity(locked ? 0.45 : 1)
        .animation(.snappy(duration: 0.25), value: granted)
        .animation(.snappy(duration: 0.25), value: locked)
    }
}

private struct ProgressBar: View {
    let progress: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(Theme.sky)
                    .frame(width: max(5, geo.size.width * progress))
            }
        }
        .frame(height: 5)
        .animation(.snappy(duration: 0.3), value: progress)
    }
}

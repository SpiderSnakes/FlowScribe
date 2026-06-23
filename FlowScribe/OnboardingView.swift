import SwiftUI
import AppKit

/// Accueil première ouverture, plein écran (pas de fenêtre dans la fenêtre) :
/// demande les permissions une par une, barre de progression qui avance.
/// Inspiré de SuperWhisper (cf. docs/design-references).
struct OnboardingView: View {
    let permissions: PermissionsModel
    var onDone: () -> Void

    private var grantedCount: Int {
        [permissions.mic == .granted, permissions.speech == .granted, permissions.accessibility]
            .filter { $0 }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressBar(progress: Double(grantedCount) / 3.0)   // pleine largeur, tout en haut
            Spacer(minLength: 0)
            content.frame(maxWidth: 480)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(VisualEffectBackground(material: .sidebar).ignoresSafeArea())
        .animation(.snappy(duration: 0.25), value: grantedCount)
        .onAppear { permissions.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissions.refresh()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Bienvenue dans FlowScribe")
                    .font(.system(size: 28, weight: .bold))
                Text("Configurons les autorisations — tout reste en local, la confidentialité d'abord.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 16) {
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
                    .buttonStyle(.glass).font(.callout)
            }

            VStack(alignment: .leading, spacing: 10) {
                Button(action: onDone) {
                    Text("Commencer à utiliser FlowScribe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!permissions.allGranted)

                if !permissions.allGranted {
                    Button("Ignorer pour l'instant", action: onDone)
                        .buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
        }
    }

    private func row(icon: String, title: String, desc: String,
                     granted: Bool, locked: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(granted ? Theme.accent : .secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(desc).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.system(size: 20))
            } else {
                Button("Autoriser", action: action).buttonStyle(.glass).disabled(locked)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
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
                Rectangle().fill(Color.primary.opacity(0.08))
                Rectangle().fill(Theme.accent)
                    .frame(width: max(0, geo.size.width * progress))
            }
        }
        .frame(height: 4)
        .animation(.snappy(duration: 0.3), value: progress)
    }
}

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
        .background {
            ZStack {
                GrainientBackground()
                AuroraView(surface: .onboarding).opacity(0.9)
                SideRaysView(surface: .onboarding)
                StrandsView(lineCount: 7, amplitude: 0.35, speed: 0.6, surface: .onboarding)
                    .opacity(0.5)
            }
            .ignoresSafeArea()
        }
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
                    state: permissions.mic, locked: false,
                    request: { Task { await permissions.requestMicrophone() } },
                    openSettings: { Permissions.openMicrophoneSettings() },
                    deniedHint: "Micro refusé : active FlowScribe dans Réglages → Micro, puis relance.")
                row(icon: "waveform", title: "Reconnaissance vocale",
                    desc: "Requise pour la transcription Apple, sur l'appareil.",
                    state: permissions.speech, locked: permissions.mic != .granted,
                    request: { Task { await permissions.requestSpeech() } },
                    openSettings: { Permissions.openMicrophoneSettings() },
                    deniedHint: "Reconnaissance vocale refusée : active-la dans Réglages → Confidentialité, puis relance.")
                row(icon: "accessibility", title: "Accessibilité",
                    desc: "Coller le texte dans tes apps (Cmd+V). Utilisée au besoin.",
                    state: permissions.accessibility ? .granted : .notDetermined,
                    locked: permissions.speech != .granted,
                    request: { permissions.requestAccessibility() },
                    openSettings: { Permissions.openAccessibilitySettings() },
                    deniedHint: nil)
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

    /// Une ligne d'autorisation. `.denied` n'est plus une impasse : on propose alors « Ouvrir les
    /// Réglages… » (au lieu d'un « Autoriser » qui ne déclenche plus aucune invite système) et un
    /// indice. macOS n'affiche le dialogue de consentement qu'une fois ; après refus, requestX() est muet.
    private func row(icon: String, title: String, desc: String,
                     state: PermissionState, locked: Bool,
                     request: @escaping () -> Void, openSettings: @escaping () -> Void,
                     deniedHint: String?) -> some View {
        let granted = state == .granted
        return VStack(alignment: .leading, spacing: 6) {
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
                        .accessibilityLabel("\(title) : autorisé")
                } else if state == .denied {
                    // Après refus, l'API ne ré-affiche pas l'invite → on redirige vers les Réglages Système.
                    Button("Ouvrir les Réglages…", action: openSettings).buttonStyle(.glass).disabled(locked)
                } else {
                    Button("Autoriser", action: request).buttonStyle(.glass).disabled(locked)
                }
            }
            if state == .denied, !locked, let deniedHint {
                Text(deniedHint).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .borderGlow(active: granted, cornerRadius: 12)
        .opacity(locked ? 0.45 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityValue(granted ? "Autorisé" : (state == .denied ? "Refusé" : "Non autorisé"))
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

import SwiftUI
import AppKit

/// Référence faible vers la fenêtre principale, partagée entre la couche AppKit (AppDelegate) et SwiftUI.
@MainActor
final class MainWindowRef {
    static let shared = MainWindowRef()
    weak var window: NSWindow?
    private init() {}
}

/// Délégué applicatif : permet à l'app de **rester lancée quand la fenêtre est fermée** (outil de fond)
/// et de **rouvrir la fenêtre** quand on relance l'app (Spotlight / clic Dock) — comportement « invisible ».
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Ne reste lancée après fermeture de la fenêtre QU'en mode arrière-plan (sinon comportement standard : quitter).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: "runInBackground")
    }

    /// Relance alors que l'app tourne déjà (Spotlight, clic Dock) → on remet la fenêtre au premier plan.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MainActor.assumeIsolated {
                MainWindowRef.shared.window?.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        return true   // si la fenêtre avait été détruite, laisse SwiftUI en recréer une
    }
}

/// Capte la `NSWindow` de la fenêtre principale (pour la réafficher plus tard) et, si demandé,
/// la masque une seule fois au lancement (démarrage invisible). N'altère PAS le délégué de la fenêtre.
struct WindowAccessor: NSViewRepresentable {
    let hideOnLaunch: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let coordinator = context.coordinator
        // makeNSView est isolé MainActor ; on diffère (la fenêtre n'est pas encore posée). updateNSView
        // est le filet : il rappelle `capture` quand la vue est bien dans la fenêtre (anti-course).
        Task { @MainActor in coordinator.capture(view.window, hideOnLaunch: hideOnLaunch) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.capture(nsView.window, hideOnLaunch: hideOnLaunch)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor final class Coordinator {
        private var launchHandled = false
        func capture(_ window: NSWindow?, hideOnLaunch: Bool) {
            guard let window else { return }
            MainWindowRef.shared.window = window
            // Le masquage ne vaut QU'au premier affichage (lancement). Un changement de réglage en cours
            // de session ne doit pas masquer la fenêtre ouverte → on verrouille après la première capture.
            guard !launchHandled else { return }
            launchHandled = true
            if hideOnLaunch { window.orderOut(nil) }
        }
    }
}

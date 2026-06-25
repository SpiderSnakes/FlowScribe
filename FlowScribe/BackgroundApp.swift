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
    /// Ne pas quitter quand la dernière fenêtre se ferme : l'app continue en tâche de fond (raccourci actif).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

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
        // makeNSView est isolé MainActor ; on diffère sur le même acteur (la fenêtre n'est pas encore posée).
        Task { @MainActor in
            guard let window = view.window else { return }
            MainWindowRef.shared.window = window
            if hideOnLaunch && !coordinator.didHide {
                coordinator.didHide = true
                window.orderOut(nil)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window { MainWindowRef.shared.window = window }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var didHide = false }
}

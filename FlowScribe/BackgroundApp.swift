import SwiftUI
import AppKit
import FlowScribeCore

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
        AppLog.info("App", "réouverture (Spotlight/Dock) — fenêtre visible=\(flag)")
        if !flag {
            MainActor.assumeIsolated {
                MainWindowRef.shared.window?.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
        return true   // si la fenêtre avait été détruite, laisse SwiftUI en recréer une
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Les instances précédentes arrêtées ici : `setup()` attendra leur sortie effective avant
        // de toucher l'état partagé (historique / dossier d'enregistrements / raccourci global).
        Self.terminatedPreviousInstances = Self.terminatePreviousInstances()
        AppLog.info("App", "lancement terminé (NSApplication prête)")
    }

    /// Instances précédentes auxquelles on a envoyé un quit (asynchrone) : `setup()` les surveille
    /// jusqu'à leur sortie effective avant de démarrer le moteur, pour éviter que deux process touchent
    /// simultanément le même historique / dossier d'enregistrements / raccourci global.
    @MainActor static var terminatedPreviousInstances: [NSRunningApplication] = []

    /// Attend (avec un court délai max) que les instances précédentes soient réellement terminées.
    /// `app.terminate()` ne fait qu'envoyer l'AppleEvent de quit et rend la main aussitôt.
    @MainActor
    static func waitForPreviousInstancesToExit(timeout: TimeInterval = 2) async {
        let others = terminatedPreviousInstances
        guard !others.isEmpty else { return }
        let deadline = Date().addingTimeInterval(timeout)
        while others.contains(where: { !$0.isTerminated }) && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)   // 50 ms
        }
        if others.contains(where: { !$0.isTerminated }) {
            AppLog.warn("App", "instance(s) précédente(s) encore active(s) après \(timeout) s — démarrage quand même")
        }
        terminatedPreviousInstances = []
    }

    /// Garantit une SEULE instance de FlowScribe. Indispensable pour une app en arrière-plan invisible :
    /// après une mise à jour, l'ANCIENNE version reste lancée (aucune icône Dock/menu pour la quitter) et
    /// entre en conflit avec la nouvelle — même raccourci global, même dossier d'enregistrements, même
    /// journal → deux moteurs qui se marchent dessus (« erreur de transcription » en boucle, relances
    /// fantômes). Le nouveau process (celui-ci) gagne : il arrête les instances précédentes du même bundle.
    @discardableResult
    private static func terminatePreviousInstances() -> [NSRunningApplication] {
        guard let bundleID = Bundle.main.bundleIdentifier else { return [] }
        let myPID = NSRunningApplication.current.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != myPID }
        for app in others {
            AppLog.warn("App", "instance FlowScribe déjà active (pid \(app.processIdentifier)) — arrêt de l'ancienne")
            if !app.terminate() { app.forceTerminate() }   // forceTerminate si le quit propre est refusé
        }
        return others
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
            AppLog.info("App", "fenêtre principale capturée (masquée au lancement=\(hideOnLaunch))")
            if hideOnLaunch { window.orderOut(nil) }
        }
    }
}

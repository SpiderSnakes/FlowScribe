import ServiceManagement
import FlowScribeCore

/// Lancement au démarrage de session (SMAppService, macOS 13+).
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Active/désactive le lancement au login et renvoie l'état EFFECTIF (relu sur le système).
    /// Un échec n'est plus avalé silencieusement : il est journalisé, et l'appelant peut réconcilier
    /// l'interrupteur avec la vérité système (cf. SettingsStore.launchAtLogin.didSet).
    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            // Échec (ex. build non signé en debug) : on journalise au lieu d'avaler en silence.
            AppLog.warn("LaunchAtLogin", "échec \(enabled ? "register" : "unregister") : \(error.localizedDescription)")
        }
        // Cas .requiresApproval : l'utilisateur doit valider dans Réglages > Éléments d'ouverture.
        if enabled && SMAppService.mainApp.status == .requiresApproval {
            AppLog.info("LaunchAtLogin", "validation requise dans Réglages > Éléments d'ouverture")
            SMAppService.openSystemSettingsLoginItems()
        }
        return isEnabled
    }
}

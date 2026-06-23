import ServiceManagement

/// Lancement au démarrage de session (SMAppService, macOS 13+).
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            // Échec silencieux (ex. non signé en debug) — l'utilisateur peut réessayer.
        }
    }
}

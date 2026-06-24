import SwiftUI
import AppKit
import FlowScribeCore

/// Style de la fenêtre d'enregistrement (HUD).
enum RecordingWindowStyle: String, CaseIterable, Identifiable, Sendable {
    case classic, mini, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .classic: return "Classic"
        case .mini: return "Mini"
        case .none: return "Aucune"
        }
    }
}

@MainActor
@Observable
final class SettingsStore {
    private let defaults = UserDefaults.standard
    private let secrets: SecretStore

    /// Notifié quand un réglage affectant le pipeline change → reconstruction à chaud.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    @ObservationIgnored private var batching = false

    /// Applique plusieurs mutations en ne notifiant `onChange` qu'une seule fois à la fin
    /// (ex. activer un mode = 6 réglages → 1 seule reconstruction du pipeline).
    func applyBatch(_ mutations: () -> Void) {
        batching = true
        mutations()
        batching = false
        onChange?()
    }
    private func notifyChange() { if !batching { onChange?() } }

    var defaultProvider: EngineProvider {
        didSet { defaults.set(defaultProvider.rawValue, forKey: "defaultProvider"); notifyChange() }
    }
    var localeIdentifier: String {
        didSet { defaults.set(localeIdentifier, forKey: "localeIdentifier"); notifyChange() }
    }
    var musicControlEnabled: Bool {
        didSet { defaults.set(musicControlEnabled, forKey: "musicControlEnabled"); notifyChange() }
    }
    var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: "cleanupEnabled"); notifyChange() }
    }
    /// Reformulation (2ᵉ passe écrite) — alimentés par le mode actif.
    var cleanupPrompt: String {
        didSet { defaults.set(cleanupPrompt, forKey: "cleanupPrompt"); notifyChange() }
    }
    /// Fournisseur écrit utilisé pour la reformulation.
    var cleanupProvider: EngineProvider {
        didSet { defaults.set(cleanupProvider.rawValue, forKey: "cleanupProvider"); notifyChange() }
    }
    /// Modèle écrit utilisé pour la reformulation.
    var cleanupModelId: String {
        didSet { defaults.set(cleanupModelId, forKey: "cleanupModelId"); notifyChange() }
    }
    static let defaultCleanupPrompt = TextLLMService.defaultPrompt
    /// Rétention de l'historique en jours (0 = illimité).
    var retentionDays: Int {
        didSet { defaults.set(retentionDays, forKey: "retentionDays") }
    }
    /// Onboarding vu au moins une fois (sinon on affiche l'accueil des permissions).
    var hasSeenOnboarding: Bool {
        didSet { defaults.set(hasSeenOnboarding, forKey: "hasSeenOnboarding") }
    }
    /// Style de la fenêtre d'enregistrement (HUD).
    var recordingWindowStyle: RecordingWindowStyle {
        didSet { defaults.set(recordingWindowStyle.rawValue, forKey: "recordingWindowStyle"); notifyChange() }
    }
    /// UID du micro choisi (vide = micro système par défaut).
    var selectedMicrophoneUID: String {
        didSet { defaults.set(selectedMicrophoneUID, forKey: "selectedMicrophoneUID"); notifyChange() }
    }
    /// Repères sonores au début/à la fin de l'enregistrement.
    var soundEffectsEnabled: Bool {
        didSet { defaults.set(soundEffectsEnabled, forKey: "soundEffectsEnabled") }
    }
    /// Lancement au démarrage de session (synchronisé avec SMAppService).
    var launchAtLogin: Bool {
        didSet { LaunchAtLogin.set(launchAtLogin) }
    }
    /// Tourner en arrière-plan : masque l'icône du Dock (l'app reste accessible via la barre de menus + raccourci).
    var runInBackground: Bool {
        didSet {
            defaults.set(runInBackground, forKey: "runInBackground")
            NSApp.setActivationPolicy(runInBackground ? .accessory : .regular)
        }
    }

    init(secrets: SecretStore) {
        self.secrets = secrets
        let raw = defaults.string(forKey: "defaultProvider") ?? ""
        self.defaultProvider = EngineProvider(rawValue: raw) ?? .appleLocal
        self.localeIdentifier = defaults.string(forKey: "localeIdentifier") ?? "fr-FR"
        self.musicControlEnabled = defaults.bool(forKey: "musicControlEnabled")
        self.cleanupEnabled = defaults.bool(forKey: "cleanupEnabled")
        self.cleanupPrompt = defaults.string(forKey: "cleanupPrompt") ?? Self.defaultCleanupPrompt
        self.cleanupProvider = EngineProvider(rawValue: defaults.string(forKey: "cleanupProvider") ?? "") ?? .openAI
        self.cleanupModelId = defaults.string(forKey: "cleanupModelId") ?? ""
        self.retentionDays = defaults.object(forKey: "retentionDays") as? Int ?? 30
        self.hasSeenOnboarding = defaults.bool(forKey: "hasSeenOnboarding")
        self.recordingWindowStyle = RecordingWindowStyle(rawValue: defaults.string(forKey: "recordingWindowStyle") ?? "") ?? .classic
        self.selectedMicrophoneUID = defaults.string(forKey: "selectedMicrophoneUID") ?? ""
        self.soundEffectsEnabled = defaults.bool(forKey: "soundEffectsEnabled")
        self.launchAtLogin = LaunchAtLogin.isEnabled
        self.runInBackground = defaults.bool(forKey: "runInBackground")
    }

    func apiKey(for provider: EngineProvider) -> String {
        guard let key = provider.secretKey else { return "" }
        return secrets.get(key) ?? ""
    }

    @discardableResult
    func setAPIKey(_ value: String, for provider: EngineProvider) -> Bool {
        guard let key = provider.secretKey else { return false }
        let ok = secrets.set(value.isEmpty ? nil : value, for: key)
        notifyChange()
        return ok
    }

    func selectedModelId(for provider: EngineProvider) -> String {
        defaults.string(forKey: "model.\(provider.rawValue)") ?? provider.defaultModelId
    }

    func setModel(_ id: String, for provider: EngineProvider) {
        defaults.set(id, forKey: "model.\(provider.rawValue)")
        notifyChange()
    }
}

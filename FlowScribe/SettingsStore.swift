import SwiftUI
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

    var defaultProvider: EngineProvider {
        didSet { defaults.set(defaultProvider.rawValue, forKey: "defaultProvider"); onChange?() }
    }
    var localeIdentifier: String {
        didSet { defaults.set(localeIdentifier, forKey: "localeIdentifier"); onChange?() }
    }
    var musicControlEnabled: Bool {
        didSet { defaults.set(musicControlEnabled, forKey: "musicControlEnabled"); onChange?() }
    }
    var cleanupEnabled: Bool {
        didSet { defaults.set(cleanupEnabled, forKey: "cleanupEnabled"); onChange?() }
    }
    /// Prompt de reformulation IA (alimenté par le mode actif).
    var cleanupPrompt: String {
        didSet { defaults.set(cleanupPrompt, forKey: "cleanupPrompt"); onChange?() }
    }
    static let defaultCleanupPrompt = "Corrige la ponctuation et la casse, retire les hésitations (euh, hum) et les répétitions, SANS changer le sens ni la langue. Réponds UNIQUEMENT le texte corrigé."
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
        didSet { defaults.set(recordingWindowStyle.rawValue, forKey: "recordingWindowStyle"); onChange?() }
    }
    /// UID du micro choisi (vide = micro système par défaut).
    var selectedMicrophoneUID: String {
        didSet { defaults.set(selectedMicrophoneUID, forKey: "selectedMicrophoneUID"); onChange?() }
    }
    /// Repères sonores au début/à la fin de l'enregistrement.
    var soundEffectsEnabled: Bool {
        didSet { defaults.set(soundEffectsEnabled, forKey: "soundEffectsEnabled") }
    }
    /// Lancement au démarrage de session (synchronisé avec SMAppService).
    var launchAtLogin: Bool {
        didSet { LaunchAtLogin.set(launchAtLogin) }
    }

    init(secrets: SecretStore) {
        self.secrets = secrets
        let raw = defaults.string(forKey: "defaultProvider") ?? ""
        self.defaultProvider = EngineProvider(rawValue: raw) ?? .appleLocal
        self.localeIdentifier = defaults.string(forKey: "localeIdentifier") ?? "fr-FR"
        self.musicControlEnabled = defaults.bool(forKey: "musicControlEnabled")
        self.cleanupEnabled = defaults.bool(forKey: "cleanupEnabled")
        self.cleanupPrompt = defaults.string(forKey: "cleanupPrompt") ?? Self.defaultCleanupPrompt
        self.retentionDays = defaults.object(forKey: "retentionDays") as? Int ?? 30
        self.hasSeenOnboarding = defaults.bool(forKey: "hasSeenOnboarding")
        self.recordingWindowStyle = RecordingWindowStyle(rawValue: defaults.string(forKey: "recordingWindowStyle") ?? "") ?? .classic
        self.selectedMicrophoneUID = defaults.string(forKey: "selectedMicrophoneUID") ?? ""
        self.soundEffectsEnabled = defaults.bool(forKey: "soundEffectsEnabled")
        self.launchAtLogin = LaunchAtLogin.isEnabled
    }

    func apiKey(for provider: EngineProvider) -> String {
        guard let key = provider.secretKey else { return "" }
        return secrets.get(key) ?? ""
    }

    func setAPIKey(_ value: String, for provider: EngineProvider) {
        guard let key = provider.secretKey else { return }
        secrets.set(value.isEmpty ? nil : value, for: key)
        onChange?()
    }

    func selectedModelId(for provider: EngineProvider) -> String {
        defaults.string(forKey: "model.\(provider.rawValue)") ?? provider.defaultModelId
    }

    func setModel(_ id: String, for provider: EngineProvider) {
        defaults.set(id, forKey: "model.\(provider.rawValue)")
        onChange?()
    }
}

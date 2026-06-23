import SwiftUI
import FlowScribeCore

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
    /// Rétention de l'historique en jours (0 = illimité).
    var retentionDays: Int {
        didSet { defaults.set(retentionDays, forKey: "retentionDays") }
    }

    init(secrets: SecretStore) {
        self.secrets = secrets
        let raw = defaults.string(forKey: "defaultProvider") ?? ""
        self.defaultProvider = EngineProvider(rawValue: raw) ?? .appleLocal
        self.localeIdentifier = defaults.string(forKey: "localeIdentifier") ?? "fr-FR"
        self.musicControlEnabled = defaults.bool(forKey: "musicControlEnabled")
        self.cleanupEnabled = defaults.bool(forKey: "cleanupEnabled")
        self.retentionDays = defaults.object(forKey: "retentionDays") as? Int ?? 30
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

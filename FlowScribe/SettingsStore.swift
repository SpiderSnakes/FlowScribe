import SwiftUI
import FlowScribeCore

@MainActor
@Observable
final class SettingsStore {
    private let defaults = UserDefaults.standard
    private let secrets: SecretStore

    var defaultProvider: EngineProvider { didSet { defaults.set(defaultProvider.rawValue, forKey: "defaultProvider") } }
    var localeIdentifier: String { didSet { defaults.set(localeIdentifier, forKey: "localeIdentifier") } }

    init(secrets: SecretStore) {
        self.secrets = secrets
        let raw = defaults.string(forKey: "defaultProvider") ?? ""
        self.defaultProvider = EngineProvider(rawValue: raw) ?? .appleLocal
        self.localeIdentifier = defaults.string(forKey: "localeIdentifier") ?? "fr-FR"
    }

    func apiKey(for provider: EngineProvider) -> String {
        guard let key = provider.secretKey else { return "" }
        return secrets.get(key) ?? ""
    }

    func setAPIKey(_ value: String, for provider: EngineProvider) {
        guard let key = provider.secretKey else { return }
        secrets.set(value.isEmpty ? nil : value, for: key)
    }
}

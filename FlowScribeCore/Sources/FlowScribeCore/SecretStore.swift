import Foundation
import Security

public protocol SecretStore: Sendable {
    /// Renvoie true si l'écriture (ou la suppression) a réussi.
    @discardableResult func set(_ value: String?, for key: String) -> Bool
    func get(_ key: String) -> String?
}

/// Store en mémoire (tests).
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()
    public init() {}
    @discardableResult public func set(_ value: String?, for key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        storage[key] = value
        return true
    }
    public func get(_ key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }
}

/// Store Keychain (prod). `service` namespace les entrées de l'app.
public final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    private let service: String
    public init(service: String = "cloud.spidersnake.FlowScribe") { self.service = service }

    @discardableResult public func set(_ value: String?, for key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)   // ignore le résultat (l'entrée peut ne pas exister)
        guard let value, let data = value.data(using: .utf8) else { return true }   // suppression réussie
        var add = query
        add[kSecValueData as String] = data
        // Borne le secret au déverrouillage de cette session/appareil (pas de migration/sauvegarde).
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    public func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

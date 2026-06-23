import Foundation

/// Portées spéciales pour les profils de correction.
public enum CorrectionScope {
    /// Règles appliquées à TOUS les moteurs (clé réservée dans le store).
    public static let global = "__global__"
}

public struct CorrectionRule: Codable, Equatable, Sendable {
    public let heard: String
    public let replacement: String
    /// Une règle désactivée est conservée mais non appliquée.
    public let enabled: Bool

    public init(heard: String, replacement: String, enabled: Bool = true) {
        self.heard = heard; self.replacement = replacement; self.enabled = enabled
    }

    // Décodage rétrocompatible : `enabled` absent (JSON hérité) → true.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        heard = try c.decode(String.self, forKey: .heard)
        replacement = try c.decode(String.self, forKey: .replacement)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
}

import Foundation

public struct PostCorrector: Sendable {
    private let store: CorrectionProfileStore
    public init(store: CorrectionProfileStore) { self.store = store }

    public func correct(_ text: String, engineId: String) -> String {
        var result = text
        // Règles les plus longues d'abord (les phrases avant les mots isolés).
        let rules = store.rules(for: engineId).sorted { $0.heard.count > $1.heard.count }
        for rule in rules {
            result = replace(rule.heard, with: rule.replacement, in: result)
        }
        return result
    }

    /// Remplacement insensible à la casse, ancré sur des frontières de mots.
    private func replace(_ heard: String, with replacement: String, in text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: heard)
        guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        let template = NSRegularExpression.escapedTemplate(for: replacement)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}

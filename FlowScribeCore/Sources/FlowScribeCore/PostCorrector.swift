import Foundation

public struct PostCorrector: Sendable {
    private let store: CorrectionProfileStore
    public init(store: CorrectionProfileStore) { self.store = store }

    public func correct(_ text: String, engineId: String) -> String {
        var result = text
        // Règles globales + propres au moteur, actives uniquement, les plus longues d'abord.
        let combined = store.rules(for: CorrectionScope.global) + store.rules(for: engineId)
        let rules = combined.filter { $0.enabled }.sorted { $0.heard.count > $1.heard.count }
        for rule in rules {
            result = replace(rule.heard, with: rule.replacement, in: result)
        }
        return result
    }

    /// Remplacement insensible à la casse. Tolère plusieurs espaces/sauts de ligne entre les
    /// mots, et n'ancre `\b` que du côté où le terme commence/finit par un caractère de mot
    /// (sinon « .NET », « c++ », « node.js » ne seraient jamais corrigés).
    private func replace(_ heard: String, with replacement: String, in text: String) -> String {
        let trimmed = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        // Échappe le terme puis autorise toute séquence d'espaces blancs entre les mots.
        let escaped = NSRegularExpression.escapedPattern(for: trimmed)
            .replacingOccurrences(of: " ", with: "\\s+")
        let leading = (trimmed.first.map(Self.isWordChar) ?? false) ? "\\b" : ""
        let trailing = (trimmed.last.map(Self.isWordChar) ?? false) ? "\\b" : ""
        guard let regex = try? NSRegularExpression(pattern: "\(leading)\(escaped)\(trailing)", options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        let template = NSRegularExpression.escapedTemplate(for: replacement)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private static func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber }
}

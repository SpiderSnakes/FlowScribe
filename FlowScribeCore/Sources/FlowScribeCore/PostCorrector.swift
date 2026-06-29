import Foundation

public struct PostCorrector: Sendable {
    private let store: CorrectionProfileStore
    public init(store: CorrectionProfileStore) { self.store = store }

    public func correct(_ text: String, engineId: String) -> String {
        // Règles globales + propres au moteur, actives uniquement.
        let combined = store.rules(for: CorrectionScope.global) + store.rules(for: engineId)
        // Une seule passe gauche→droite sur le texte ORIGINAL : à chaque position on choisit le match
        // le plus précoce puis le plus long parmi toutes les règles, puis on avance APRÈS la portion
        // substituée. Ainsi le texte déjà émis n'est jamais re-scanné : pas de cascade (la sortie d'une
        // règle ne peut pas re-déclencher une autre règle), et plus de dépendance à un tri instable.
        let rules: [(regex: NSRegularExpression, replacement: String)] = combined
            .filter { $0.enabled }
            // `heard` trimé, les plus longs d'abord : départage déterministe pour des longueurs égales.
            .compactMap { rule -> (String, NSRegularExpression, String)? in
                let trimmed = rule.heard.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, let regex = Self.makeRegex(for: trimmed) else { return nil }
                return (trimmed, regex, rule.replacement)
            }
            .sorted { ($0.0.count, $0.0) > ($1.0.count, $1.0) }
            .map { ($0.1, $0.2) }
        guard !rules.isEmpty else { return text }

        let ns = text as NSString
        var result = ""
        var cursor = 0
        let total = ns.length
        while cursor < total {
            let remaining = NSRange(location: cursor, length: total - cursor)
            // Cherche, parmi toutes les règles, le match dont la position de départ est la plus à gauche ;
            // à position égale, on garde le plus long (les règles sont déjà triées par longueur décroissante).
            var best: (range: NSRange, replacement: String)?
            for (regex, replacement) in rules {
                guard let m = regex.firstMatch(in: text, options: [], range: remaining) else { continue }
                if let b = best {
                    if m.range.location < b.range.location
                        || (m.range.location == b.range.location && m.range.length > b.range.length) {
                        best = (m.range, replacement)
                    }
                } else {
                    best = (m.range, replacement)
                }
            }
            guard let match = best else {
                // Plus aucun match : recopie le reste tel quel.
                result += ns.substring(from: cursor)
                break
            }
            // Recopie le texte avant le match, émet le remplacement, puis avance après la portion substituée.
            if match.range.location > cursor {
                result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            result += match.replacement
            cursor = match.range.location + match.range.length
        }
        return result
    }

    /// Construit la regex insensible à la casse pour un terme. Tolère plusieurs espaces/sauts de ligne
    /// entre les mots, et n'ancre `\b` que du côté où le terme commence/finit par un caractère de mot
    /// (sinon « .NET », « c++ », « node.js » ne seraient jamais corrigés).
    private static func makeRegex(for trimmed: String) -> NSRegularExpression? {
        let escaped = NSRegularExpression.escapedPattern(for: trimmed)
            .replacingOccurrences(of: " ", with: "\\s+")
        let leading = (trimmed.first.map(isWordChar) ?? false) ? "\\b" : ""
        let trailing = (trimmed.last.map(isWordChar) ?? false) ? "\\b" : ""
        return try? NSRegularExpression(pattern: "\(leading)\(escaped)\(trailing)", options: [.caseInsensitive])
    }

    private static func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber }
}

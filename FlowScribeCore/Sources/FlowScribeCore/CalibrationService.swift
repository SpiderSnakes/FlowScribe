import Foundation

public enum CalibrationService {
    /// Compare la lecture (hypothèse) au texte de référence et propose des règles
    /// `entendu → terme` pour chaque terme du glossaire mal transcrit.
    public static func proposeRules(reference: String, hypothesis: String, glossary: [String]) -> [CorrectionRule] {
        let refTokens = Aligner.tokenize(reference)
        let hypTokens = Aligner.tokenize(hypothesis)
        let pairs = Aligner.align(reference: refTokens, hypothesis: hypTokens)

        // Pré-tokenise chaque terme du glossaire : on compare des SÉQUENCES de tokens (« visual studio »
        // → ["visual", "studio"]) et non plus une clé mono-token, sinon les termes multi-mots
        // (« Visual Studio », « GitHub Actions »…) n'étaient jamais détectés. On garde la forme d'affichage.
        // Trié par longueur de séquence décroissante : on tente d'abord les correspondances les plus longues.
        let terms: [(tokens: [String], canonical: String)] = glossary
            .map { (Aligner.tokenize($0), $0) }
            .filter { !$0.0.isEmpty }
            .sorted { $0.0.count > $1.0.count }

        var rules: [CorrectionRule] = []
        var idx = 0
        while idx < pairs.count {
            // Fenêtre glissante : la séquence de référence à partir de `idx` correspond-elle à un terme ?
            // On ignore les paires d'insertion (reference == nil) à l'intérieur de la fenêtre.
            if let matched = matchTerm(at: idx, in: pairs, terms: terms) {
                let heard = matched.heardTokens.joined(separator: " ")
                // N'émet une règle que si l'entendu diffère réellement du terme attendu.
                if !heard.isEmpty, heard.caseInsensitiveCompare(matched.canonical) != .orderedSame {
                    rules.append(CorrectionRule(heard: heard, replacement: matched.canonical))
                }
                idx = matched.nextIndex; continue
            }
            idx += 1
        }
        return rules
    }

    /// Tente de faire correspondre, à partir de `start`, la séquence de tokens de référence à un terme
    /// du glossaire. Renvoie les tokens d'hypothèse couvrant la fenêtre (`heard`), la forme canonique et
    /// l'indice de reprise. Capte aussi les insertions adjacentes (mot scindé : « doc » + « ploy »).
    private static func matchTerm(at start: Int, in pairs: [AlignedPair],
                                  terms: [(tokens: [String], canonical: String)])
        -> (heardTokens: [String], canonical: String, nextIndex: Int)? {
        for term in terms {
            var heardTokens: [String] = []
            var refMatched = 0          // nombre de tokens de référence du terme déjà consommés
            var k = start
            while k < pairs.count, refMatched < term.tokens.count {
                let pair = pairs[k]
                if let ref = pair.reference {
                    // Le token de référence doit correspondre au token attendu du terme.
                    guard ref == term.tokens[refMatched] else { break }
                    if let h = pair.hypothesis { heardTokens.append(h) }
                    refMatched += 1; k += 1
                } else if let h = pair.hypothesis {
                    // Insertion (ref nil) : fait partie de l'entendu (mot scindé).
                    heardTokens.append(h); k += 1
                } else {
                    break
                }
            }
            guard refMatched == term.tokens.count else { continue }
            // Capte les insertions adjacentes après la fenêtre (fin de mot scindé).
            while k < pairs.count, pairs[k].reference == nil, let h = pairs[k].hypothesis {
                heardTokens.append(h); k += 1
            }
            return (heardTokens, term.canonical, k)
        }
        return nil
    }
}

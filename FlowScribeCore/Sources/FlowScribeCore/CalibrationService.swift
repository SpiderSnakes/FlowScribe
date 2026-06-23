import Foundation

public enum CalibrationService {
    /// Compare la lecture (hypothèse) au texte de référence et propose des règles
    /// `entendu → terme` pour chaque terme du glossaire mal transcrit.
    public static func proposeRules(reference: String, hypothesis: String, glossary: [String]) -> [CorrectionRule] {
        let refTokens = Aligner.tokenize(reference)
        let hypTokens = Aligner.tokenize(hypothesis)
        let pairs = Aligner.align(reference: refTokens, hypothesis: hypTokens)
        let canonical = Dictionary(glossary.map { ($0.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })

        var rules: [CorrectionRule] = []
        var idx = 0
        while idx < pairs.count {
            let pair = pairs[idx]
            // Un terme du glossaire dans la référence, mal entendu (substitution) ?
            if let ref = pair.reference, let term = canonical[ref], let firstHyp = pair.hypothesis, ref != firstHyp {
                var heardTokens = [firstHyp]
                // Capter les insertions adjacentes (ref nil) = mot scindé ("doc" + "ploy").
                var k = idx + 1
                while k < pairs.count, pairs[k].reference == nil, let h = pairs[k].hypothesis {
                    heardTokens.append(h); k += 1
                }
                rules.append(CorrectionRule(heard: heardTokens.joined(separator: " "), replacement: term))
                idx = k; continue
            }
            idx += 1
        }
        return rules
    }
}

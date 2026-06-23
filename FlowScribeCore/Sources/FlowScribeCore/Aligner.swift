import Foundation

public struct AlignedPair: Equatable, Sendable {
    public let reference: String?
    public let hypothesis: String?
    public init(reference: String?, hypothesis: String?) {
        self.reference = reference; self.hypothesis = hypothesis
    }
}

public enum Aligner {
    public static func tokenize(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Alignement de tokens (Needleman-Wunsch, coût 1 pour sub/insert/delete).
    public static func align(reference: [String], hypothesis: [String]) -> [AlignedPair] {
        let n = reference.count, m = hypothesis.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let cost = reference[i-1] == hypothesis[j-1] ? 0 : 1
                    dp[i][j] = min(dp[i-1][j-1] + cost, dp[i-1][j] + 1, dp[i][j-1] + 1)
                }
            }
        }
        var pairs: [AlignedPair] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            // 1. correspondance exacte (diagonale, coût 0)
            if i > 0 && j > 0 && reference[i-1] == hypothesis[j-1] && dp[i][j] == dp[i-1][j-1] {
                pairs.append(AlignedPair(reference: reference[i-1], hypothesis: hypothesis[j-1]))
                i -= 1; j -= 1; continue
            }
            // 2. insertion (consomme l'hypothèse) — regroupe les insertions en fin de terme
            if j > 0 && dp[i][j] == dp[i][j-1] + 1 {
                pairs.append(AlignedPair(reference: nil, hypothesis: hypothesis[j-1]))
                j -= 1; continue
            }
            // 3. substitution (diagonale, coût 1)
            if i > 0 && j > 0 && dp[i][j] == dp[i-1][j-1] + 1 {
                pairs.append(AlignedPair(reference: reference[i-1], hypothesis: hypothesis[j-1]))
                i -= 1; j -= 1; continue
            }
            // 4. délétion (consomme la référence)
            pairs.append(AlignedPair(reference: reference[i-1], hypothesis: nil))
            i -= 1
        }
        return pairs.reversed()
    }
}

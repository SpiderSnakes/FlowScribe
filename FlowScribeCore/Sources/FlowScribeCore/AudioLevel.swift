import Foundation

public enum AudioLevel {
    /// Niveau RMS normalisé 0→1 (1 = pleine échelle).
    public static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        let value = (sumSquares / Float(samples.count)).squareRoot()
        return min(1, max(0, value))
    }
}

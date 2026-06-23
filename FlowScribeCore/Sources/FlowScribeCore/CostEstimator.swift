import Foundation

public enum CostEstimator {
    public static func estimateUSD(durationSeconds: TimeInterval, pricePerMinuteUSD: Double) -> Double {
        max(0, durationSeconds) / 60.0 * pricePerMinuteUSD
    }
    public static func formatted(_ usd: Double) -> String {
        String(format: "$%.4f", usd)
    }
}

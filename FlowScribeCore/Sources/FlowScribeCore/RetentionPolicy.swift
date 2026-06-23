import Foundation

public enum RetentionPolicy {
    /// Records expirés (plus vieux que `maxAgeDays`). `maxAgeDays <= 0` ⇒ aucun n'expire.
    public static func expired(_ records: [TranscriptionRecord], now: Date, maxAgeDays: Int) -> [TranscriptionRecord] {
        guard maxAgeDays > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-Double(maxAgeDays) * 86_400)
        return records.filter { $0.date < cutoff }
    }
}

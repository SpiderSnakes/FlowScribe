import Foundation

public protocol CorrectionProfileStore: Sendable {
    func rules(for engineId: String) -> [CorrectionRule]
    func setRules(_ rules: [CorrectionRule], for engineId: String)
    func add(_ rule: CorrectionRule, for engineId: String)
}

public final class InMemoryCorrectionProfileStore: CorrectionProfileStore, @unchecked Sendable {
    private var byEngine: [String: [CorrectionRule]] = [:]
    private let lock = NSLock()
    public init() {}
    public func rules(for engineId: String) -> [CorrectionRule] {
        lock.lock(); defer { lock.unlock() }; return byEngine[engineId] ?? []
    }
    public func setRules(_ rules: [CorrectionRule], for engineId: String) {
        lock.lock(); defer { lock.unlock() }; byEngine[engineId] = rules
    }
    public func add(_ rule: CorrectionRule, for engineId: String) {
        lock.lock(); defer { lock.unlock() }
        var arr = byEngine[engineId] ?? []
        if !arr.contains(where: { $0.heard.caseInsensitiveCompare(rule.heard) == .orderedSame }) { arr.append(rule) }
        byEngine[engineId] = arr
    }
}

/// Persistance JSON (Application Support). Charge en mémoire, réécrit à chaque modification.
public final class JSONCorrectionProfileStore: CorrectionProfileStore, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var byEngine: [String: [CorrectionRule]]

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: [CorrectionRule]].self, from: data) {
            byEngine = decoded
        } else {
            byEngine = [:]
        }
    }
    public func rules(for engineId: String) -> [CorrectionRule] {
        lock.lock(); defer { lock.unlock() }; return byEngine[engineId] ?? []
    }
    public func setRules(_ rules: [CorrectionRule], for engineId: String) {
        lock.lock(); defer { lock.unlock() }
        byEngine[engineId] = rules; persistLocked()
    }
    public func add(_ rule: CorrectionRule, for engineId: String) {
        lock.lock(); defer { lock.unlock() }
        var arr = byEngine[engineId] ?? []
        if !arr.contains(where: { $0.heard.caseInsensitiveCompare(rule.heard) == .orderedSame }) { arr.append(rule) }
        byEngine[engineId] = arr
        persistLocked()
    }
    /// Écrit SOUS le verrou → sérialise snapshot ET écriture (pas d'entrelacement entre threads).
    private func persistLocked() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do { try JSONEncoder().encode(byEngine).write(to: url, options: .atomic) }
        catch { AppLog.error("CorrectionProfileStore", "échec d'écriture des corrections : \(error)") }
    }
}

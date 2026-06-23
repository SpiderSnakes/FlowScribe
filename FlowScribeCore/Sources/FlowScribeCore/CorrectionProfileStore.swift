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
        if !arr.contains(rule) { arr.append(rule) }
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
        lock.lock(); byEngine[engineId] = rules; lock.unlock(); persist()
    }
    public func add(_ rule: CorrectionRule, for engineId: String) {
        lock.lock()
        var arr = byEngine[engineId] ?? []
        if !arr.contains(rule) { arr.append(rule) }
        byEngine[engineId] = arr
        lock.unlock(); persist()
    }
    private func persist() {
        lock.lock(); let snapshot = byEngine; lock.unlock()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url) }
    }
}

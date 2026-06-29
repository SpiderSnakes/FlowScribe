import Foundation

public protocol GlossaryStore: Sendable {
    var terms: [String] { get }
    func add(_ term: String)
    func remove(_ term: String)
}

public final class InMemoryGlossaryStore: GlossaryStore, @unchecked Sendable {
    private var storage: [String] = []
    private let lock = NSLock()
    public init() {}
    public var terms: [String] { lock.lock(); defer { lock.unlock() }; return storage }
    public func add(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        if !storage.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) { storage.append(t) }
    }
    public func remove(_ term: String) {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
    }
}

public final class JSONGlossaryStore: GlossaryStore, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var storage: [String]
    public init(url: URL) {
        self.url = url
        // Distingue « absent » (1er lancement → vide) de « présent mais corrompu » (sauvegarde avant écrasement).
        storage = JSONStorePersistence.loadOrBackup(url: url, category: "GlossaryStore", default: [String]()) {
            try JSONDecoder().decode([String].self, from: $0)
        }
    }
    public var terms: [String] { lock.lock(); defer { lock.unlock() }; return storage }
    public func add(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        if !storage.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) { storage.append(t) }
        persistLocked()
    }
    public func remove(_ term: String) {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }; persistLocked()
    }
    /// Écrit SOUS le verrou → sérialise snapshot ET écriture (pas d'entrelacement entre threads).
    private func persistLocked() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do { try JSONEncoder().encode(storage).write(to: url, options: .atomic) }
        catch { AppLog.error("GlossaryStore", "échec d'écriture du glossaire : \(error)") }
    }
}

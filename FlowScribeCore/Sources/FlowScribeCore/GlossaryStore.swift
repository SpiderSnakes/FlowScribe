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
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([String].self, from: data) {
            storage = decoded
        } else { storage = [] }
    }
    public var terms: [String] { lock.lock(); defer { lock.unlock() }; return storage }
    public func add(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        lock.lock()
        if !storage.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) { storage.append(t) }
        lock.unlock(); persist()
    }
    public func remove(_ term: String) {
        lock.lock(); storage.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }; lock.unlock(); persist()
    }
    private func persist() {
        lock.lock(); let snap = storage; lock.unlock()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snap) { try? data.write(to: url, options: .atomic) }
    }
}

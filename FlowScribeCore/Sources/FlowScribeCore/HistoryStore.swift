import Foundation

public protocol HistoryStore: Sendable {
    var records: [TranscriptionRecord] { get }   // plus récent d'abord
    func add(_ record: TranscriptionRecord)
    /// Remplace l'enregistrement de même id de façon atomique (une seule prise de verrou, une seule persistance) :
    /// pas de fenêtre où l'entrée disparaît (re-transcription en place).
    func update(_ record: TranscriptionRecord)
    func delete(id: UUID)
}

public final class InMemoryHistoryStore: HistoryStore, @unchecked Sendable {
    private var storage: [TranscriptionRecord] = []
    private let lock = NSLock()
    public init() {}
    public var records: [TranscriptionRecord] {
        lock.lock(); defer { lock.unlock() }; return storage.sorted { $0.date > $1.date }
    }
    public func add(_ record: TranscriptionRecord) {
        lock.lock(); defer { lock.unlock() }; storage.append(record)
    }
    public func update(_ record: TranscriptionRecord) {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll { $0.id == record.id }; storage.append(record)
    }
    public func delete(id: UUID) {
        lock.lock(); defer { lock.unlock() }; storage.removeAll { $0.id == id }
    }
}

public final class JSONHistoryStore: HistoryStore, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var storage: [TranscriptionRecord]

    public init(url: URL) {
        self.url = url
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url), let decoded = try? dec.decode([TranscriptionRecord].self, from: data) {
            storage = decoded
        } else {
            storage = []
        }
    }
    public var records: [TranscriptionRecord] {
        lock.lock(); defer { lock.unlock() }; return storage.sorted { $0.date > $1.date }
    }
    public func add(_ record: TranscriptionRecord) {
        lock.lock(); defer { lock.unlock() }
        storage.append(record); persistLocked()
    }
    public func update(_ record: TranscriptionRecord) {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll { $0.id == record.id }; storage.append(record); persistLocked()
    }
    public func delete(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll { $0.id == id }; persistLocked()
    }
    /// Écrit SOUS le verrou : sérialise snapshot ET écriture → pas d'entrelacement entre threads (anti perte).
    private func persistLocked() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        do { try enc.encode(storage).write(to: url, options: .atomic) }
        catch { AppLog.error("HistoryStore", "échec d'écriture de l'historique : \(error)") }
    }
}

import Foundation

public protocol ModeStore: Sendable {
    var modes: [Mode] { get }
    var activeModeId: UUID? { get }
    /// Ajoute le mode, ou le remplace s'il existe déjà (même id).
    func upsert(_ mode: Mode)
    func delete(id: UUID)
    func setActive(_ id: UUID)
}

public final class InMemoryModeStore: ModeStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Mode] = []
    private var active: UUID?
    public init() {}

    public var modes: [Mode] { lock.lock(); defer { lock.unlock() }; return storage }
    public var activeModeId: UUID? { lock.lock(); defer { lock.unlock() }; return active }

    public func upsert(_ mode: Mode) {
        lock.lock(); defer { lock.unlock() }
        if let i = storage.firstIndex(where: { $0.id == mode.id }) { storage[i] = mode } else { storage.append(mode) }
    }
    public func delete(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll { $0.id == id }
        if active == id { active = storage.first?.id }
    }
    public func setActive(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        if storage.contains(where: { $0.id == id }) { active = id }
    }
}

/// Persistance JSON (Application Support) : { modes, activeModeId }.
public final class JSONModeStore: ModeStore, @unchecked Sendable {
    private struct Payload: Codable { var modes: [Mode]; var activeModeId: UUID? }
    private let url: URL
    private let lock = NSLock()
    private var payload: Payload

    public init(url: URL) {
        self.url = url
        // Distingue « absent » (1er lancement → vide) de « présent mais corrompu » (sauvegarde avant écrasement).
        payload = JSONStorePersistence.loadOrBackup(url: url, category: "ModeStore",
                                                    default: Payload(modes: [], activeModeId: nil)) {
            try JSONDecoder().decode(Payload.self, from: $0)
        }
    }

    public var modes: [Mode] { lock.lock(); defer { lock.unlock() }; return payload.modes }
    public var activeModeId: UUID? { lock.lock(); defer { lock.unlock() }; return payload.activeModeId }

    public func upsert(_ mode: Mode) {
        lock.lock(); defer { lock.unlock() }
        if let i = payload.modes.firstIndex(where: { $0.id == mode.id }) { payload.modes[i] = mode } else { payload.modes.append(mode) }
        persistLocked()
    }
    public func delete(id: UUID) {
        lock.lock(); defer { lock.unlock() }
        payload.modes.removeAll { $0.id == id }
        if payload.activeModeId == id { payload.activeModeId = payload.modes.first?.id }
        persistLocked()
    }
    public func setActive(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        if payload.modes.contains(where: { $0.id == id }) { payload.activeModeId = id }
        persistLocked()
    }

    /// Écrit SOUS le verrou → sérialise snapshot ET écriture (pas d'entrelacement entre threads).
    private func persistLocked() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do { try JSONEncoder().encode(payload).write(to: url, options: .atomic) }
        catch { AppLog.error("ModeStore", "échec d'écriture des modes : \(error)") }
    }
}

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
        // Distingue « fichier absent » (1er lancement → vide) de « présent mais illisible/corrompu »
        // (on NE réinitialise PAS à vide en silence : on sauvegarde le fichier suspect avant tout écrasement).
        storage = JSONStorePersistence.loadOrBackup(url: url, category: "HistoryStore", default: [TranscriptionRecord]()) {
            try dec.decode([TranscriptionRecord].self, from: $0)
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

/// Chargement défensif partagé par les stores JSON.
///
/// Distingue deux cas que l'ancien `try? decode` confondait :
/// - **fichier absent** (1er lancement légitime) → conteneur vide, aucune trace ;
/// - **fichier présent mais illisible/corrompu** → on NE réinitialise PAS en silence. On journalise
///   une erreur et on déplace le fichier suspect vers un sidecar `.corrupt-<horodatage>` AVANT que la
///   1re écriture ne l'écrase, de sorte qu'une récupération manuelle reste possible.
enum JSONStorePersistence {
    static func loadOrBackup<T>(url: URL, category: String, default fallback: T,
                                decode: (Data) throws -> T) -> T {
        let fm = FileManager.default
        guard let data = try? Data(contentsOf: url) else {
            // Pas de données : soit le fichier n'existe pas (1er lancement), soit lecture impossible.
            if fm.fileExists(atPath: url.path) {
                AppLog.error(category, "fichier présent mais illisible : \(url.lastPathComponent)")
            }
            return fallback
        }
        do {
            return try decode(data)
        } catch {
            // Le fichier existe et contient des octets, mais le décodage échoue → corruption probable.
            AppLog.error(category, "fichier corrompu/illisible (\(url.lastPathComponent)) : \(error) — sauvegarde avant écrasement")
            let stamp = String(Int(Date().timeIntervalSince1970))
            let backup = url.appendingPathExtension("corrupt-\(stamp)")
            do { try fm.moveItem(at: url, to: backup) }
            catch { AppLog.error(category, "échec de la sauvegarde du fichier corrompu : \(error)") }
            return fallback
        }
    }
}

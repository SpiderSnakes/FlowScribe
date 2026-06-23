import SwiftUI
import FlowScribeCore

@MainActor
@Observable
final class HistoryModel {
    private let store: HistoryStore
    private let recordingsDir: URL
    var records: [TranscriptionRecord] = []

    init(store: HistoryStore, recordingsDir: URL) {
        self.store = store
        self.recordingsDir = recordingsDir
        records = store.records
    }

    func add(_ r: TranscriptionRecord) {
        store.add(r)
        records = store.records
    }

    func delete(_ r: TranscriptionRecord) {
        store.delete(id: r.id)
        deleteAudio(r.audioFileName)
        records = store.records
    }

    func purge(maxAgeDays: Int) {
        for r in RetentionPolicy.expired(store.records, now: Date(), maxAgeDays: maxAgeDays) {
            store.delete(id: r.id)
            deleteAudio(r.audioFileName)
        }
        records = store.records
    }

    /// Copie un fichier audio externe dans le dossier `recordings` sous un nom unique, renvoie ce nom.
    func importAudio(from source: URL, id: UUID) throws -> String {
        let name = FileImporter.importedFileName(for: source, id: id)
        let dest = audioURL(name)
        try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
        try FileManager.default.copyItem(at: source, to: dest)
        return name
    }

    func audioURL(_ name: String) -> URL { recordingsDir.appending(path: name) }
    func audioExists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: audioURL(name).path) }
    private func deleteAudio(_ name: String) { try? FileManager.default.removeItem(at: audioURL(name)) }
}

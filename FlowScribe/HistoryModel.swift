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

    /// Remplace un enregistrement en place (même id), SANS toucher au fichier audio —
    /// utilisé par la re-transcription pour mettre à jour le texte/statut sans dupliquer ni perdre l'audio.
    /// `store.update` est atomique (une persistance), donc pas de fenêtre où l'entrée disparaît.
    func update(_ r: TranscriptionRecord) {
        store.update(r)
        records = store.records
    }

    func delete(_ r: TranscriptionRecord) {
        store.delete(id: r.id)
        deleteAudio(r.audioFileName)
        records = store.records
    }

    /// Supprime toutes les transcriptions et leurs fichiers audio.
    func deleteAll() {
        for r in store.records {
            store.delete(id: r.id)
            deleteAudio(r.audioFileName)
        }
        records = store.records
    }

    func purge(maxAgeDays: Int) {
        for r in RetentionPolicy.expired(store.records, now: Date(), maxAgeDays: maxAgeDays) {
            store.delete(id: r.id)
            deleteAudio(r.audioFileName)
        }
        records = store.records
    }

    /// Récupère au lancement les enregistrements laissés orphelins par un crash :
    /// un `.caf` = enregistrement interrompu avant la conversion à l'arrêt ;
    /// un `.wav` = conversion faite mais historique non écrit (crash dans l'intervalle).
    /// Convertit les CAF en WAV vérifié (hors thread principal), puis crée une entrée « récupéré »
    /// pour chaque fichier sans transcription — l'utilisateur peut alors relancer la transcription.
    /// Aucune perte d'audio : la conversion ne supprime le CAF qu'après vérification du WAV.
    func recoverOrphans(defaultLocale: String) async {
        let fm = FileManager.default
        func orphanNames(ext: String) -> [String] {
            let known = Set(store.records.map(\.audioFileName))
            let entries = (try? fm.contentsOfDirectory(at: recordingsDir,
                                                       includingPropertiesForKeys: nil,
                                                       options: [.skipsHiddenFiles])) ?? []
            return entries
                .filter { $0.pathExtension.lowercased() == ext && !known.contains($0.lastPathComponent) }
                .map(\.lastPathComponent)
        }
        // 1) CAF interrompus → conversion (hors-main) en WAV vérifié.
        var recoveredFromCAF: [String] = []
        for cafName in orphanNames(ext: "caf") {
            let caf = audioURL(cafName)
            let wav = await Task.detached(priority: .utility) {
                AudioConverter.convertToWAV(caf, deleteSourceOnSuccess: true)
            }.value
            if let wav {
                recoveredFromCAF.append(wav.lastPathComponent)
            } else {
                // Conversion impossible : on historise le CAF TEL QUEL plutôt que de le laisser invisible
                // et re-scanné (donc re-tenté) à chaque lancement. Il devient visible dans l'historique et
                // reste relançable via ElevenLabs (qui accepte le .caf). Une entrée existante l'exclut des
                // prochains scans d'orphelins → pas de boucle de re-tentative.
                AppLog.warn("History", "récupération : conversion impossible pour \(cafName) — entrée CAF conservée")
                recoveredFromCAF.append(cafName)
            }
        }
        // historise les CAF récupérés AVANT de lister les WAV orphelins (sinon doublon).
        for name in recoveredFromCAF { addRecovered(named: name, defaultLocale: defaultLocale) }
        // 2) WAV terminés mais sans entrée d'historique.
        let wavOrphans = orphanNames(ext: "wav")
        for name in wavOrphans { addRecovered(named: name, defaultLocale: defaultLocale) }

        let total = recoveredFromCAF.count + wavOrphans.count
        if total > 0 {
            records = store.records
            AppLog.info("History", "récupération : \(total) enregistrement(s) orphelin(s) restauré(s)")
        }
    }

    /// Crée une entrée d'historique « récupéré » (sans texte, audio conservé) pour un fichier orphelin.
    private func addRecovered(named name: String, defaultLocale: String) {
        let duration = AudioConverter.duration(of: audioURL(name))
        store.add(TranscriptionRecord(
            id: UUID(), date: Date(), text: "", engineId: "",
            locale: defaultLocale, audioFileName: name, duration: duration,
            errorMessage: "Enregistrement récupéré après une fermeture inattendue — relance la transcription."))
        AppLog.info("History", "récupéré \(name) (\(duration.map { String(format: "%.1fs", $0) } ?? "?"))")
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
    private func deleteAudio(_ name: String) {
        guard !name.isEmpty else { return }   // sécurité : éviter de cibler le dossier recordings entier
        try? FileManager.default.removeItem(at: audioURL(name))
    }
}

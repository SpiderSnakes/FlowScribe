import Foundation

/// Génère le nom sous lequel un fichier audio importé est copié dans le dossier
/// `recordings`, aux côtés des `.caf` de dictée. Logique pure et testable.
public enum FileImporter {
    /// Nom de fichier unique pour l'audio importé, en conservant l'extension d'origine (en minuscules).
    /// Sans extension, renvoie l'UUID seul.
    public static func importedFileName(for source: URL, id: UUID) -> String {
        let ext = source.pathExtension.lowercased()
        return ext.isEmpty ? id.uuidString : "\(id.uuidString).\(ext)"
    }
}

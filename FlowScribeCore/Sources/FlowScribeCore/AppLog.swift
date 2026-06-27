import Foundation
import os

/// Journalisation légère : écrit dans un FICHIER (que l'utilisateur peut transmettre pour diagnostiquer
/// un bug) ET dans le log unifié macOS (visible dans Console.app). Thread-safe : tout accès au fichier,
/// à `fileURL` et au formateur passe sous un verrou. Bas débit → coût négligeable.
public enum AppLog {
    public enum Level: String, Sendable { case info = "INFO", warn = "WARN", error = "ERROR" }

    /// Emplacement du fichier de log. `var` pour permettre aux tests de pointer vers un dossier temporaire ;
    /// toute lecture/écriture passe sous `lock`, donc pas de course même si un test le réassigne.
    nonisolated(unsafe) public static var fileURL: URL =
        URL.applicationSupportDirectory.appending(path: "FlowScribe/logs/flowscribe.log")

    private static let lock = NSLock()
    private static let osLog = os.Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "cloud.spidersnake.FlowScribe", category: "flowscribe")
    /// Formateur réutilisé (allocation coûteuse) — accédé uniquement sous `lock`.
    nonisolated(unsafe) private static let iso = ISO8601DateFormatter()

    public static func info(_ category: String, _ message: @autoclosure () -> String)  { write(.info, category, message()) }
    public static func warn(_ category: String, _ message: @autoclosure () -> String)  { write(.warn, category, message()) }
    public static func error(_ category: String, _ message: @autoclosure () -> String) { write(.error, category, message()) }

    /// Contenu du fichier de log (pour affichage/partage).
    public static func read() -> String {
        lock.lock(); defer { lock.unlock() }
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    /// Vide le fichier de log.
    public static func clear() {
        lock.lock(); defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Privé

    private static func write(_ level: Level, _ category: String, _ message: String) {
        switch level {                                  // os.Logger est Sendable & thread-safe → hors verrou
        case .info:  osLog.info("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .warn:  osLog.warning("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .error: osLog.error("[\(category, privacy: .public)] \(message, privacy: .public)")
        }
        lock.lock(); defer { lock.unlock() }
        let url = fileURL                               // instantané sous verrou
        let line = "[\(iso.string(from: Date()))] [\(level.rawValue)] [\(category)] \(message)\n"
        appendLocked(line, to: url)
    }

    /// Préconditions : appelé sous `lock`.
    private static func appendLocked(_ line: String, to url: URL) {
        guard let data = line.data(using: .utf8) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
        rotateLocked(url)
    }

    /// Rotation simple (sous `lock`) : au-delà de ~5 Mo, on ne garde que la seconde moitié (entrées récentes).
    /// Plafond volontairement large : on veut le MAXIMUM d'historique pour diagnostiquer un bug a posteriori.
    private static func rotateLocked(_ url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int, size > 5_000_000,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let trimmed = String(content.suffix(content.count / 2))
        try? trimmed.data(using: .utf8)?.write(to: url)
    }
}

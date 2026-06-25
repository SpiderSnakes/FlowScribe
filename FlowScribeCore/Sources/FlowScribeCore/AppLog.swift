import Foundation
import os

/// Journalisation légère : écrit dans un FICHIER (que l'utilisateur peut transmettre pour diagnostiquer
/// un bug) ET dans le log unifié macOS (visible dans Console.app). Thread-safe : les écritures fichier
/// sont sérialisées sous verrou. Bas débit (quelques lignes par transcription) → coût négligeable.
public enum AppLog {
    public enum Level: String, Sendable { case info = "INFO", warn = "WARN", error = "ERROR" }

    /// Emplacement du fichier de log. `var` pour permettre aux tests de pointer vers un dossier temporaire.
    nonisolated(unsafe) public static var fileURL: URL =
        URL.applicationSupportDirectory.appending(path: "FlowScribe/logs/flowscribe.log")

    private static let lock = NSLock()
    nonisolated(unsafe) private static let osLog = os.Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "cloud.spidersnake.FlowScribe", category: "flowscribe")

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
        switch level {
        case .info:  osLog.info("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .warn:  osLog.warning("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .error: osLog.error("[\(category, privacy: .public)] \(message, privacy: .public)")
        }
        let line = "[\(Self.timestamp())] [\(level.rawValue)] [\(category)] \(message)\n"
        lock.lock(); defer { lock.unlock() }
        appendLocked(line)
    }

    private static func appendLocked(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
        rotateLocked()
    }

    /// Rotation simple : au-delà de ~2 Mo, on ne garde que la seconde moitié (les entrées récentes).
    private static func rotateLocked() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? Int, size > 2_000_000,
              let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let trimmed = String(content.suffix(content.count / 2))
        try? trimmed.data(using: .utf8)?.write(to: fileURL)
    }

    private static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

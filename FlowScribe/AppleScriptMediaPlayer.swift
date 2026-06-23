import Foundation
import FlowScribeCore

/// Contrôle Music.app / Spotify via AppleScript (aucune API privée).
/// Nécessite l'entitlement com.apple.security.automation.apple-events + NSAppleEventsUsageDescription.
struct AppleScriptMediaPlayer: MediaPlayer {
    private func appName(_ s: MediaSource) -> String { s == .music ? "Music" : "Spotify" }

    @discardableResult
    private func run(_ script: String) -> String? {
        var error: NSDictionary?
        let descriptor = NSAppleScript(source: script)?.executeAndReturnError(&error)
        return descriptor?.stringValue
    }

    func isPlaying(_ s: MediaSource) -> Bool {
        let app = appName(s)
        let script = """
        if application "\(app)" is running then
            tell application "\(app)" to return (player state as text)
        end if
        return "stopped"
        """
        return run(script)?.lowercased().contains("playing") ?? false
    }

    func pause(_ s: MediaSource) {
        let app = appName(s)
        run("if application \"\(app)\" is running then tell application \"\(app)\" to pause")
    }

    func play(_ s: MediaSource) {
        let app = appName(s)
        run("if application \"\(app)\" is running then tell application \"\(app)\" to play")
    }
}

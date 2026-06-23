import Foundation
import AppKit

public protocol TextOutput: Sendable {
    func deliver(_ text: String)
}

/// Écriture presse-papier isolée pour être testable.
public enum Clipboard {
    public static func write(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

/// Sortie réelle : copie dans le presse-papier système puis simule Cmd+V.
public final class SystemTextOutput: TextOutput {
    public init() {}

    public func deliver(_ text: String) {
        Clipboard.write(text, to: .general)
        Self.simulatePaste()
    }

    /// Simule un Cmd+V via CGEvent (nécessite la permission Accessibilité).
    private static func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09 // 'v'
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

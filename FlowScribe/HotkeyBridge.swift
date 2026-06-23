import Foundation
import AppKit
import KeyboardShortcuts
import FlowScribeCore

extension KeyboardShortcuts.Name {
    static let toggleDictation = Self("toggleDictation", default: .init(.space, modifiers: [.option]))
}

/// Traduit le raccourci global en appels au contrôleur. Le HUD est piloté par
/// `DictationController.onStateChange`/`onFinish` (donc identique pour le bouton et le hotkey).
@MainActor
final class HotkeyBridge {
    private let controller: DictationController
    private let holdThreshold: TimeInterval = 0.25
    private var pressDownAt: Date?

    init(controller: DictationController) {
        self.controller = controller
        register()
    }

    private func register() {
        KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [weak self] in
            self?.pressDownAt = Date()
            self?.controller.pressDown()
        }
        KeyboardShortcuts.onKeyUp(for: .toggleDictation) { [weak self] in
            guard let self else { return }
            let duration = self.pressDownAt.map { Date().timeIntervalSince($0) } ?? 0
            let kind = PressClassifier.classify(pressDuration: duration, holdThreshold: self.holdThreshold)
            Task { await self.controller.pressUp(kind: kind) }
        }
    }
}

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

    private var localEscMonitor: Any?
    private var globalEscMonitor: Any?
    private let escapeKeyCode: UInt16 = 53

    init(controller: DictationController) {
        self.controller = controller
        register()
        registerEscape()
    }
    // Pas de deinit : HotkeyBridge vit toute la durée de l'app ; les monitors NSEvent
    // sont libérés à la terminaison du process.

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

    /// Échap annule la dictée en cours (local : consomme l'événement ; global : observe).
    private func registerEscape() {
        localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == self.escapeKeyCode, self.controller.state != .idle else { return event }
            Task { await self.controller.cancel() }
            return nil   // consomme l'Échap (n'annule pas une feuille/un champ par-dessus)
        }
        globalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == self.escapeKeyCode, self.controller.state != .idle else { return }
            Task { await self.controller.cancel() }
        }
    }
}

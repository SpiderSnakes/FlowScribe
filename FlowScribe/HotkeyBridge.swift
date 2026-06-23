import Foundation
import AppKit
import KeyboardShortcuts
import FlowScribeCore

extension KeyboardShortcuts.Name {
    static let toggleDictation = Self("toggleDictation", default: .init(.space, modifiers: [.option]))
}

@MainActor
final class HotkeyBridge {
    private let controller: DictationController
    private let hud: RecordingHUD
    private let holdThreshold: TimeInterval = 0.25
    private var pressDownAt: Date?

    init(controller: DictationController, hud: RecordingHUD) {
        self.controller = controller
        self.hud = hud
        register()
    }

    private func register() {
        KeyboardShortcuts.onKeyDown(for: .toggleDictation) { [weak self] in
            guard let self else { return }
            self.pressDownAt = Date()
            self.controller.pressDown()
            self.hud.show(state: self.controller.state)
        }
        KeyboardShortcuts.onKeyUp(for: .toggleDictation) { [weak self] in
            guard let self else { return }
            let duration = self.pressDownAt.map { Date().timeIntervalSince($0) } ?? 0
            let kind = PressClassifier.classify(pressDuration: duration, holdThreshold: self.holdThreshold)
            Task {
                await self.controller.pressUp(kind: kind)
                if self.controller.state == .idle { self.hud.hide() }
                else { self.hud.show(state: self.controller.state) }
            }
        }
    }
}

import SwiftUI
import FlowScribeCore

@MainActor
@Observable
final class ModesModel {
    private let store: ModeStore
    var modes: [Mode]
    var activeModeId: UUID?

    init(store: ModeStore) {
        self.store = store
        modes = store.modes
        activeModeId = store.activeModeId
    }

    var activeMode: Mode? { modes.first { $0.id == activeModeId } }

    func upsert(_ mode: Mode) {
        store.upsert(mode)
        modes = store.modes
    }

    func delete(_ mode: Mode) {
        store.delete(id: mode.id)
        modes = store.modes
        activeModeId = store.activeModeId
    }

    func setActive(_ id: UUID) {
        store.setActive(id)
        activeModeId = store.activeModeId
    }
}

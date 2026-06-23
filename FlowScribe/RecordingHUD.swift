import AppKit
import SwiftUI
import FlowScribeCore

struct HUDView: View {
    let state: DictationState
    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(state == .recording ? Color.red : Color.orange)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }
    private var label: String {
        switch state {
        case .idle: return "Prêt"
        case .recording: return "Enregistrement…"
        case .transcribing: return "Transcription…"
        }
    }
}

@MainActor
final class RecordingHUD {
    private var panel: NSPanel?

    func show(state: DictationState) {
        let panel = self.panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: HUDView(state: state))
        positionBottomCenter(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return panel
    }

    private func positionBottomCenter(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 80))
    }
}

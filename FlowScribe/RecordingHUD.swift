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
                .fixedSize(horizontal: true, vertical: false)
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

struct ResultHUDView: View {
    let message: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

@MainActor
final class RecordingHUD {
    private var panel: NSPanel?

    func show(state: DictationState) {
        present(NSHostingView(rootView: HUDView(state: state)))
    }

    /// Affiche un toast de résultat (moteur utilisé / repli) puis se masque seul.
    func showResult(_ message: String) {
        present(NSHostingView(rootView: ResultHUDView(message: message)))
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            self.hide()
        }
    }

    func hide() { panel?.orderOut(nil) }

    private func present(_ hosting: NSView) {
        let panel = self.panel ?? makePanel()
        panel.contentView = hosting
        let fit = hosting.fittingSize
        panel.setContentSize(NSSize(width: max(fit.width, 120), height: max(fit.height, 36)))
        positionBottomCenter(panel)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 220, height: 44),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
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

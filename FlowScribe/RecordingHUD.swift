import AppKit
import SwiftUI
import FlowScribeCore

struct ResultHUDView: View {
    let message: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.sky)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(Theme.glassTint, in: .capsule)
        .glassEffect(.clear, in: .capsule)
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

@MainActor
final class RecordingHUD {
    private var panel: NSPanel?
    private let model = HUDModel()
    private var showingResult = false

    func show(state: DictationState) {
        model.state = state
        presentLive()
    }

    func setLevel(_ level: Float) {
        model.level = Double(max(0, min(1, level)))
    }

    /// Toast de résultat (moteur utilisé / repli), restylé bleu, auto-masqué.
    func showResult(_ message: String) {
        let panel = self.panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: ResultHUDView(message: message))
        showingResult = true
        sizeToFit(panel, fallback: NSSize(width: 200, height: 44))
        panel.orderFrontRegardless()
        self.panel = panel
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            self.hide()
        }
    }

    func hide() { panel?.orderOut(nil); showingResult = false }

    private func presentLive() {
        let panel = self.panel ?? makePanel()
        if showingResult || !(panel.contentView is NSHostingView<LiveHUDView>) {
            panel.contentView = NSHostingView(rootView: LiveHUDView(model: model))
            showingResult = false
            panel.setContentSize(NSSize(width: 280, height: 88))
            positionBottomCenter(panel)
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func sizeToFit(_ panel: NSPanel, fallback: NSSize) {
        let fit = panel.contentView?.fittingSize ?? fallback
        panel.setContentSize(NSSize(width: max(fit.width, 120), height: max(fit.height, 36)))
        positionBottomCenter(panel)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 88),
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

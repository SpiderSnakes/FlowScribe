import AppKit
import SwiftUI
import FlowScribeCore

struct ResultHUDView: View {
    let message: String
    var isError: Bool = false
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? Color.orange : Theme.sky)
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
    /// Style de fenêtre choisi (mis à jour depuis les réglages).
    var style: RecordingWindowStyle = .classic
    /// Palette + intensité de l'ambiance (injectée dans le NSHostingView côté HUD).
    var ambiance = Ambiance(palette: BrandPalette(.nuitBleue), intensity: .equilibre)
    private var liveStyle: RecordingWindowStyle?

    func show(state: DictationState) {
        if state == .recording && model.state != .recording { model.resetLevels() }
        model.state = state
        presentLive()
    }

    func setLevel(_ level: Float) {
        model.pushLevel(Double(level))
    }

    /// Toast de résultat (moteur utilisé / repli), restylé bleu, auto-masqué.
    func showResult(_ message: String, isError: Bool = false) {
        let panel = self.panel ?? makePanel()
        panel.contentView = clearHosting(ResultHUDView(message: message, isError: isError))
        showingResult = true
        sizeToFit(panel, fallback: NSSize(width: 200, height: 44))
        panel.orderFrontRegardless()
        self.panel = panel
        let seconds = isError ? 3.5 : 1.6   // un échec reste affiché plus longtemps
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            self.hide()
        }
    }

    func hide() { panel?.orderOut(nil); showingResult = false; model.stop() }

    private func presentLive() {
        guard style != .none else { hide(); return }
        let panel = self.panel ?? makePanel()
        let needsRebuild = showingResult || liveStyle != style || !(panel.contentView is NSHostingView<AnyView>)
        if needsRebuild {
            let size: NSSize
            switch style {
            case .classic:
                panel.contentView = clearHosting(AnyView(ClassicHUDView(model: model).environment(\.ambiance, ambiance)))
                size = NSSize(width: 412, height: 120)
            case .mini:
                panel.contentView = clearHosting(AnyView(LiveHUDView(model: model).environment(\.ambiance, ambiance)))
                size = NSSize(width: 280, height: 88)
            case .none:
                return
            }
            showingResult = false
            liveStyle = style
            panel.setContentSize(size)
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

    /// Hôte SwiftUI au fond transparent : sans ça, le fond opaque par défaut du NSHostingView
    /// déborde derrière le `.clipShape` arrondi et fait apparaître des coins rectangulaires.
    private func clearHosting<Content: View>(_ root: Content) -> NSHostingView<Content> {
        let view = NSHostingView(rootView: root)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor   // NSView n'a pas de backgroundColor : on passe par le layer
        return view
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 88),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false   // l'ombre arrondie est gérée côté SwiftUI (évite le contour rectangulaire)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true   // déplaçable : on attrape n'importe où dans la fenêtre
        return panel
    }

    private func positionBottomCenter(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 80))
    }
}

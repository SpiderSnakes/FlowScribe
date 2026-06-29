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
    /// Jeton de génération : un hide() différé (toast) ne doit s'appliquer qu'à SA présentation.
    /// Incrémenté à chaque show/presentLive/showResult/hide → invalide tout hide() en attente
    /// dès qu'une nouvelle dictée (ou un nouveau toast) prend la main.
    private var generation = 0
    /// L'utilisateur a glissé le panneau : on cesse alors de le re-centrer aux reconstructions.
    private var userPositioned = false
    /// Vrai pendant un repositionnement programmatique : ignore le windowDidMove qu'il déclenche.
    private var repositioning = false
    /// Délégué qui observe les déplacements du panneau (cf. userPositioned).
    private var moveObserver: PanelMoveObserver?

    func show(state: DictationState) {
        let wasRecording = model.state == .recording
        // Synchronise la politique « Réduire les animations » avant de poser des niveaux.
        model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if state == .recording && !wasRecording { model.resetLevels() }
        model.state = state
        presentLive()
        // Annonce VoiceOver à l'entrée en enregistrement (le panneau non-activant ne reçoit jamais le focus).
        if state == .recording && !wasRecording { announce("Dictée démarrée") }
    }

    func setLevel(_ level: Float) {
        model.pushLevel(Double(level))
    }

    /// Toast de résultat (moteur utilisé / repli), restylé bleu, auto-masqué.
    func showResult(_ message: String, isError: Bool = false) {
        let panel = self.panel ?? makePanel()
        panel.contentView = clearHosting(ResultHUDView(message: message, isError: isError))
        showingResult = true
        generation &+= 1            // tout hide() différé d'une présentation antérieure devient caduc
        let gen = generation
        sizeToFit(panel, fallback: NSSize(width: 200, height: 44))
        panel.orderFrontRegardless()
        self.panel = panel
        // Annonce VoiceOver du résultat (priorité haute en cas d'échec).
        announce(message, priority: isError ? .high : .medium)
        let seconds = isError ? 3.5 : 1.6   // un échec reste affiché plus longtemps
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            // N'éteint que SI ce toast est toujours celui à l'écran : une dictée relancée
            // entre-temps a bumpé `generation` et présenté un HUD live à ne pas masquer.
            guard self.generation == gen, self.showingResult else { return }
            self.hide()
        }
    }

    func hide() { generation &+= 1; panel?.orderOut(nil); showingResult = false; model.stop() }

    private func presentLive() {
        guard style != .none else { hide(); return }
        generation &+= 1            // toute présentation live invalide un hide() de toast en attente
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
            // Ne re-centre qu'à la première présentation : respecte une position glissée par l'utilisateur.
            if !userPositioned { positionBottomCenter(panel) }
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func sizeToFit(_ panel: NSPanel, fallback: NSSize) {
        let fit = panel.contentView?.fittingSize ?? fallback
        panel.setContentSize(NSSize(width: max(fit.width, 120), height: max(fit.height, 36)))
        if !userPositioned { positionBottomCenter(panel) }
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
        // Mémorise le déplacement utilisateur pour ne plus re-centrer aux reconstructions
        // (en ignorant les déplacements programmatiques de positionBottomCenter).
        let observer = PanelMoveObserver { [weak self] in
            guard let self, !self.repositioning else { return }
            self.userPositioned = true
        }
        panel.delegate = observer
        moveObserver = observer
        return panel
    }

    private func positionBottomCenter(_ panel: NSPanel) {
        // L'écran réel du panneau (multi-moniteurs), pas systématiquement l'écran principal.
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        repositioning = true
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 80))
        repositioning = false
    }

    /// Annonce passive à VoiceOver : le NSPanel non-activant ne reçoit jamais le focus,
    /// donc l'état (démarrage/résultat) doit être poussé explicitement.
    private func announce(_ message: String, priority: NSAccessibilityPriorityLevel = .medium) {
        guard !message.isEmpty else { return }
        NSAccessibility.post(element: NSApp as Any,
                             notification: .announcementRequested,
                             userInfo: [.announcement: message,
                                        .priority: priority.rawValue])
    }
}

/// Délégué léger : signale dès que l'utilisateur déplace le panneau du HUD.
private final class PanelMoveObserver: NSObject, NSWindowDelegate {
    private let onMove: () -> Void
    init(onMove: @escaping () -> Void) { self.onMove = onMove }
    func windowDidMove(_ notification: Notification) { onMove() }
}

# R0 — Identité bleue & HUD signature — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development ou executing-plans. (Cette session : exécution inline.)

**Goal:** Donner une identité bleue à FlowScribe et un HUD « vivant » qui ondule au niveau de la voix pendant la dictée (sans transcription temps réel).

**Architecture:** `AudioLevel.rms` (fonction pure, testée) calcule un niveau 0→1 ; `MicrophoneRecorder` le publie en direct via `onLevel` ; un `HUDModel` observable porte état + niveau ; `LiveHUDView` (SwiftUI `Canvas`+`TimelineView`) dessine ondulations + lueur mouvante en verre bleu ; `RecordingHUD` héberge le tout et expose `setLevel`. Un `Theme` central porte la palette.

**Tech Stack:** Swift 6, FlowScribeCore (SPM), SwiftUI (`Canvas`, `TimelineView`, `glassEffect`), AVFoundation, XCTest.

## Global Constraints
- macOS 26+, Apple Silicon, Swift 6 strict.
- **Aucune transcription temps réel** : le HUD est un indicateur d'écoute réactif au son, pas du texte.
- Palette **bleue** (bleu nuit → bleu ciel) centralisée dans `Theme` (app, SwiftUI `Color`) ; accent appliqué globalement.
- `AudioLevel.rms` = fonction pure, **cible TDD**. Le reste (thème, HUD animé, NSPanel) = build + recette visuelle.
- Niveau audio : RMS normalisé 0→1, délivré sur le main pour l'UI.
- Périmètre R0 : identité + HUD uniquement. Pas de sidebar/historique/fournisseurs (R1+). Logo bleu fourni plus tard.
- Commits fréquents (français + trailer Co-Authored-By), push sur `origin r0-identite-hud`.

## Structure de fichiers
```
FlowScribeCore/Sources/FlowScribeCore/
├── AudioLevel.swift          fonction pure RMS (testée)
├── AudioRecorder.swift       (modifié) MicrophoneRecorder.onLevel publie le niveau
FlowScribe/
├── Theme.swift               palette bleue + dégradés (SwiftUI)
├── LiveHUDView.swift         HUDModel (@Observable) + LiveHUDView (Canvas/TimelineView)
├── RecordingHUD.swift        (refonte) héberge LiveHUDView, expose setLevel + showResult restylé
└── FlowScribeApp.swift       (modifié) accent bleu + câblage recorder.onLevel -> hud.setLevel
```

---

### Task 1: `AudioLevel.rms` (fonction pure, TDD)
**Files:** Create `FlowScribeCore/Sources/FlowScribeCore/AudioLevel.swift` ; Test `FlowScribeCore/Tests/FlowScribeCoreTests/AudioLevelTests.swift`.
**Interfaces:** `enum AudioLevel { static func rms(_ samples: [Float]) -> Float }` — racine de la moyenne des carrés, bornée 0→1.

- [ ] **Step 1: Test (échoue)**
```swift
import XCTest
@testable import FlowScribeCore

final class AudioLevelTests: XCTestCase {
    func test_empty_isZero() { XCTAssertEqual(AudioLevel.rms([]), 0, accuracy: 1e-6) }
    func test_silence_isZero() { XCTAssertEqual(AudioLevel.rms([0, 0, 0, 0]), 0, accuracy: 1e-6) }
    func test_fullScale_isOne() { XCTAssertEqual(AudioLevel.rms([1, -1, 1, -1]), 1, accuracy: 1e-6) }
    func test_louder_isHigher() {
        XCTAssertGreaterThan(AudioLevel.rms([0.5, -0.5]), AudioLevel.rms([0.1, -0.1]))
    }
    func test_clampedToOne() { XCTAssertEqual(AudioLevel.rms([4, -4]), 1, accuracy: 1e-6) }
}
```
- [ ] **Step 2: RED** — `cd FlowScribeCore && swift test --filter AudioLevelTests`.
- [ ] **Step 3: `AudioLevel.swift`**
```swift
import Foundation

public enum AudioLevel {
    /// Niveau RMS normalisé 0→1 (1 = pleine échelle).
    public static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        let value = (sumSquares / Float(samples.count)).squareRoot()
        return min(1, max(0, value))
    }
}
```
- [ ] **Step 4: GREEN**.
- [ ] **Step 5: Commit** `feat(r0): AudioLevel.rms (niveau RMS pur, testé)`.

---

### Task 2: `MicrophoneRecorder.onLevel` (publication du niveau)
**Files:** Modify `FlowScribeCore/Sources/FlowScribeCore/AudioRecorder.swift`.
**Interfaces:** `MicrophoneRecorder` gagne `public var onLevel: (@Sendable (Float) -> Void)?` ; pendant l'enregistrement, chaque buffer du tap calcule `AudioLevel.rms` et appelle `onLevel` sur le main.
> Glue audio : pas de test unitaire (le RMS est déjà testé) ; build + recette.

- [ ] **Step 1: Modifier `MicrophoneRecorder`** — ajouter la propriété et l'émission dans le tap. Remplacer le bloc `installTap` de `start()` par :
```swift
    public var onLevel: (@Sendable (Float) -> Void)?

    public func start() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let url = outputDirectory.appending(path: "rec-\(Int(Date().timeIntervalSince1970)).caf")
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        let levelHandler = onLevel
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            try? audioFile.write(from: buffer)
            guard let levelHandler, let ch = buffer.floatChannelData else { return }
            let n = Int(buffer.frameLength)
            let level = AudioLevel.rms(Array(UnsafeBufferPointer(start: ch[0], count: n)))
            DispatchQueue.main.async { levelHandler(level) }
        }
        engine.prepare()
        try engine.start()
        self.file = audioFile
        self.currentURL = url
        self.startedAt = Date()
    }
```
(le reste de la classe inchangé : `stop()`, propriétés).
- [ ] **Step 2: Build** `cd FlowScribeCore && swift build` → complete.
- [ ] **Step 3: Commit** `feat(r0): MicrophoneRecorder publie le niveau audio live (onLevel)`.

---

### Task 3: `Theme` (palette bleue)
**Files:** Create `FlowScribe/Theme.swift`.
**Interfaces:** `enum Theme` exposant `midnight`, `deepNight`, `sky` (SwiftUI `Color`), `accent`, `backgroundGradient`, `glowColor`.
> Build + œil.

- [ ] **Step 1: `Theme.swift`**
```swift
import SwiftUI

enum Theme {
    static let deepNight = Color(red: 0.02, green: 0.05, blue: 0.14)
    static let midnight  = Color(red: 0.05, green: 0.10, blue: 0.24)
    static let sky       = Color(red: 0.40, green: 0.70, blue: 0.98)
    static let accent    = sky

    static let backgroundGradient = LinearGradient(
        colors: [deepNight, midnight],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let glowColor = sky
}
```
- [ ] **Step 2: Build app** `cd .. && xcodegen generate && xcodebuild -project FlowScribe.xcodeproj -scheme FlowScribe -destination 'platform=macOS' build` → SUCCEEDED (fichier compilé même si pas encore utilisé).
- [ ] **Step 3: Commit** `feat(r0): Theme (palette bleue centralisée)`.

---

### Task 4: `LiveHUDView` + refonte `RecordingHUD`
**Files:** Create `FlowScribe/LiveHUDView.swift` ; Modify `FlowScribe/RecordingHUD.swift`.
**Interfaces:**
- Produces: `@MainActor @Observable final class HUDModel { var state: DictationState; var level: Double }` ; `struct LiveHUDView: View` (init `model:`).
- `RecordingHUD` : `func show(state:)`, `func setLevel(_ level: Float)`, `func showResult(_ message: String)`, `func hide()` (API conservée ; contenu refondu).
> Build + recette visuelle.

- [ ] **Step 1: `LiveHUDView.swift`**
```swift
import SwiftUI
import FlowScribeCore

@MainActor
@Observable
final class HUDModel {
    var state: DictationState = .idle
    var level: Double = 0
}

struct LiveHUDView: View {
    let model: HUDModel

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Theme.backgroundGradient
                // Lueur bleue qui dérive lentement.
                RadialGradient(colors: [Theme.glowColor.opacity(0.55), .clear],
                               center: UnitPoint(x: 0.5 + 0.32 * cos(t * 0.6),
                                                 y: 0.5 + 0.32 * sin(t * 0.8)),
                               startRadius: 2, endRadius: 120)
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    let base = min(size.width, size.height) / 2
                    let recording = model.state == .recording
                    let amp = recording ? (0.25 + 0.75 * model.level) : 0.12
                    // Anneaux concentriques (ondulations).
                    for i in 0..<3 {
                        let phase = (t * 0.8 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        let r = base * (0.3 + phase * 0.9 * amp)
                        let opacity = (1 - phase) * (recording ? 0.9 : 0.35)
                        let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
                        ctx.stroke(Path(ellipseIn: rect), with: .color(Theme.sky.opacity(opacity)), lineWidth: 2)
                    }
                    // Noyau : respire au repos, pulse à la voix.
                    let breath = 0.5 + 0.5 * sin(t * 2)
                    let coreR = base * (recording ? (0.18 + 0.16 * model.level) : (0.16 + 0.04 * breath))
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - coreR, y: c.y - coreR, width: 2 * coreR, height: 2 * coreR)),
                             with: .color(Theme.sky))
                }
            }
        }
        .frame(width: 260, height: 72)
        .clipShape(Capsule())
        .glassEffect(.regular, in: .capsule)
    }
}
```
- [ ] **Step 2: Refonte `RecordingHUD.swift`** (remplacer le fichier) :
```swift
import AppKit
import SwiftUI
import FlowScribeCore

struct ResultHUDView: View {
    let message: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.sky)
            Text(message).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
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

    func showResult(_ message: String) {
        let panel = panel ?? makePanel()
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
        let panel = panel ?? makePanel()
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
```
- [ ] **Step 3: Build app** → SUCCEEDED.
- [ ] **Step 4: Commit** `feat(r0): HUD signature animé (ondulations + lueur, verre bleu)`.

---

### Task 5: Câblage du niveau + accent + recette (PORTE HUMAINE)
**Files:** Modify `FlowScribe/FlowScribeApp.swift`.
**Interfaces:** Consomme `MicrophoneRecorder.onLevel`, `RecordingHUD.setLevel`, `Theme`.
> Build + recette visuelle (œil + voix).

- [ ] **Step 1: Câbler `onLevel -> setLevel` et appliquer l'accent** — dans `setup()`, créer le recorder et le HUD séparément, relier le niveau, et passer le HUD au bridge ; appliquer `.tint(Theme.accent)` à la fenêtre. Remplacer le corps de `setup()` par :
```swift
    @MainActor
    private func setup() async {
        permissions.refresh()
        await permissions.requestAll()
        guard controller == nil else { return }
        let dir = URL.applicationSupportDirectory.appending(path: "FlowScribe/recordings")
        let recorder = MicrophoneRecorder(outputDirectory: dir)
        let hud = RecordingHUD()
        recorder.onLevel = { level in
            Task { @MainActor in hud.setLevel(level) }
        }
        let c = DictationController(
            recorder: recorder,
            service: Self.makeService(from: settings, profiles: profiles),
            output: SystemTextOutput(),
            locale: Locale(identifier: settings.localeIdentifier)
        )
        Self.applyOptions(to: c, settings: settings)
        controller = c
        bridge = HotkeyBridge(controller: c, hud: hud)
        settings.onChange = { [weak c, settings, profiles] in
            guard let c else { return }
            c.configure(service: Self.makeService(from: settings, profiles: profiles),
                        locale: Locale(identifier: settings.localeIdentifier))
            Self.applyOptions(to: c, settings: settings)
        }
    }
```
> Note : `recorder.onLevel` est `@Sendable` ; on repasse sur le main via `Task { @MainActor in ... }` pour appeler `hud.setLevel`. Le `DispatchQueue.main.async` côté recorder + ce `Task` sont redondants mais sûrs ; garder le `@Sendable` simple côté closure.

- [ ] **Step 2: Appliquer l'accent bleu** — sur le `WindowGroup` racine, ajouter `.tint(Theme.accent)` au `VStack` (ou au niveau de la scène). Exemple : après `.frame(width: 380)` ajouter `.tint(Theme.accent)`.
- [ ] **Step 3: Build app** → SUCCEEDED.
- [ ] **Step 4: Recette manuelle (PORTE HUMAINE)** : relancer l'app, ⌥Espace → le HUD bleu apparaît, **ondule quand tu parles** (anneaux + noyau qui suivent la voix), lueur qui dérive ; à l'arrêt, pulsation puis toast « via … » restylé bleu. Vérifier la fluidité (~60 fps).
- [ ] **Step 5: Commit** `feat(r0): câblage niveau audio -> HUD + accent bleu`.

---

## Auto-revue (à l'écriture)
- **Couverture spec** : Thème (T3), niveau audio RMS pur+testé (T1) + publication (T2), HUD états/ondulations/lueur (T4), câblage + accent + recette (T5). ✅
- **Hors R0** : sidebar/historique/fournisseurs/fichiers/vocabulaire/motion global — étapes R1-R6.
- **Placeholders** : aucun ; T1 code+test complets, T2-T5 code complet. Couleurs hex fixées (ajustables à l'œil).
- **Cohérence types** : `AudioLevel.rms([Float])->Float`, `MicrophoneRecorder.onLevel`, `HUDModel{state,level}`, `LiveHUDView(model:)`, `RecordingHUD.show(state:)/setLevel(_:)/showResult(_:)/hide()`, `Theme.accent/sky/backgroundGradient/glowColor` cohérents.
- **Limite assumée** : HUD/animation non testés unitairement (visuel) → recette manuelle T5 ; seul le RMS est en TDD.

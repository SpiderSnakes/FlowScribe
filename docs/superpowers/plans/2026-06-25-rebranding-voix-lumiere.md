# Rebranding « Voix → Lumière » — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the validated "Voix → Lumière" visual rebrand (strands + grainient + aurora + side-rays + border-glow) across onboarding and the app, with user-selectable palette and effect-intensity in Settings.

**Architecture:** A small **testable core** (`FlowScribeCore/Ambiance.swift`: palette→RGBA mapping + a single `ambianceAnimates(...)` animation-policy function) drives a thin **SwiftUI brand layer** in the app (`BrandPalette`, an `Ambiance` value injected via `EnvironmentValues.ambiance`). Reusable view bricks (`GrainientBackground`, `AuroraView`, `SideRaysView`, `StrandsView`, `.borderGlow()`) read the environment and gate every `TimelineView` on the animation policy. Settings persists `ambiancePalette` + `ambianceIntensity` via the existing `didSet`/`UserDefaults` pattern.

**Tech Stack:** Swift 6, SwiftUI + AppKit, macOS 26 SDK (MeshGradient, `TimelineView(.animation(paused:))`, `AngularGradient`, `controlActiveState`, `accessibilityReduceMotion`, Canvas), Core Image (`CIRandomGenerator`) for grain. No new third-party dependencies. XcodeGen project.

## Global Constraints

- macOS 26 native APIs only; **no new third-party dependency**.
- **No effect may depend exclusively on a custom `.metal` shader** — every brick must work with pure SwiftUI (MeshGradient/Canvas/gradients/CIRandomGenerator). Metal shaders are an optional later upgrade.
- API keys stay in the Keychain (untouched). UI copy in **French**.
- **Do not regress** the recent HUD fixes (transparent corners via `layer.backgroundColor`, 60 fps smoothing, timer in `.common` mode) or the robustness work (failed-record recovery, atomic `HistoryStore.update`).
- Respect the system **"Réduire les animations"** (reduce-motion → fully static) and **pause main-window animations when the window is inactive** (except `.showcase`).
- Default palette = **Nuit bleue**; default intensity = **Équilibré**. **Gradient Blinds is dropped.**
- Neutral text/UI in all palettes (white/grey); palette colors drive **accents only**.
- New app files live in `FlowScribe/`; after creating one, run `xcodegen generate` before building (the project globs the folder).
- Build check: `R=/Users/spidersnake/Documents/Dev/FlowScribe; (cd "$R" && xcodegen generate); xcodebuild -project "$R/FlowScribe.xcodeproj" -scheme FlowScribe -configuration Debug -derivedDataPath "$R/build" build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"` — must print `** BUILD SUCCEEDED **`.
- Core tests: `swift test --package-path "$R/FlowScribeCore" 2>&1 | grep -E "All tests|failure"`.
- Spec: `docs/superpowers/specs/2026-06-25-rebranding-voix-lumiere-design.md`.

---

## File Structure

**Core (FlowScribeCore/Sources/FlowScribeCore/):**
- Create `Ambiance.swift` — `AmbiancePalette`, `AmbianceIntensity`, `AmbianceSurface` enums; `RGBA`; `PaletteColors`; `AmbiancePalette.colors`; `ambianceAnimates(...)`. Pure, no SwiftUI.
- Test `FlowScribeCore/Tests/FlowScribeCoreTests/AmbianceTests.swift`.

**App (FlowScribe/):**
- Create `BrandPalette.swift` — `RGBA.color`, `BrandPalette`, `Ambiance`, `EnvironmentValues.ambiance`, French `title` extensions.
- Create `GrainientBackground.swift` — base gradient + grain overlay (`CIRandomGenerator`).
- Create `BorderGlow.swift` — `.borderGlow(active:cornerRadius:)` modifier.
- Create `AuroraView.swift` — animated `MeshGradient` + blur.
- Create `SideRaysView.swift` — gradient cone + blur + shimmer.
- Create `StrandsView.swift` — generalized flowing-lines renderer (from the HUD waveform).
- Modify `SettingsStore.swift` — add `ambiancePalette`, `ambianceIntensity` (persisted).
- Modify `SettingsView.swift` — add "Apparence" section.
- Modify `FlowScribeApp.swift` — inject `\.ambiance`; thread palette into `RecordingHUD`.
- Modify `Theme.swift` — accent derived from palette (kept minimal).
- Modify `OnboardingView.swift` — brand hero background.
- Modify `HomeView.swift`, `TranscriptionDetailView.swift`, `RootView.swift`, `ClassicHUDView.swift`, `LiveHUDView.swift`, `HUDWaveform.swift`, `RecordingHUD.swift`, `VisualEffectBackground.swift` — apply bricks.

---

## Task 1: Core Ambiance model (palette colors + animation policy)

**Files:**
- Create: `FlowScribeCore/Sources/FlowScribeCore/Ambiance.swift`
- Test: `FlowScribeCore/Tests/FlowScribeCoreTests/AmbianceTests.swift`

**Interfaces:**
- Produces: `enum AmbiancePalette: String, CaseIterable, Sendable, Codable { case nuitBleue, auroreFroide, auroreDuale }`; `enum AmbianceIntensity: String, CaseIterable, Sendable, Codable { case discret, equilibre, showcase }`; `enum AmbianceSurface: Sendable { case onboarding, hud, appWindow }`; `struct RGBA` (`r,g,b,a: Double`, `init(_:_:_:_:)`, `init(hex:a:)`); `struct PaletteColors` (roles); `var AmbiancePalette.colors: PaletteColors`; `func ambianceAnimates(intensity:surface:reduceMotion:windowActive:) -> Bool`.

- [ ] **Step 1: Write the failing test**

```swift
// FlowScribeCore/Tests/FlowScribeCoreTests/AmbianceTests.swift
import XCTest
@testable import FlowScribeCore

final class AmbianceTests: XCTestCase {
    // --- Animation policy (cahier §4) ---
    func test_reduceMotion_disablesEverything() {
        for i in AmbianceIntensity.allCases {
            for s in [AmbianceSurface.onboarding, .hud, .appWindow] {
                XCTAssertFalse(ambianceAnimates(intensity: i, surface: s, reduceMotion: true, windowActive: true))
            }
        }
    }
    func test_hud_alwaysAnimates_unlessReduceMotion() {
        for i in AmbianceIntensity.allCases {
            XCTAssertTrue(ambianceAnimates(intensity: i, surface: .hud, reduceMotion: false, windowActive: false))
        }
    }
    func test_onboarding_staticOnlyInDiscret() {
        XCTAssertFalse(ambianceAnimates(intensity: .discret, surface: .onboarding, reduceMotion: false, windowActive: true))
        XCTAssertTrue(ambianceAnimates(intensity: .equilibre, surface: .onboarding, reduceMotion: false, windowActive: true))
        XCTAssertTrue(ambianceAnimates(intensity: .showcase, surface: .onboarding, reduceMotion: false, windowActive: true))
    }
    func test_appWindow_equilibre_pausesWhenInactive() {
        XCTAssertTrue(ambianceAnimates(intensity: .equilibre, surface: .appWindow, reduceMotion: false, windowActive: true))
        XCTAssertFalse(ambianceAnimates(intensity: .equilibre, surface: .appWindow, reduceMotion: false, windowActive: false))
    }
    func test_appWindow_discret_neverAnimates() {
        XCTAssertFalse(ambianceAnimates(intensity: .discret, surface: .appWindow, reduceMotion: false, windowActive: true))
    }
    func test_appWindow_showcase_animatesEvenInactive() {
        XCTAssertTrue(ambianceAnimates(intensity: .showcase, surface: .appWindow, reduceMotion: false, windowActive: false))
    }
    // --- Palette mapping ---
    func test_rgba_hexDecodes() {
        let c = RGBA(hex: 0x5B8DEF)
        XCTAssertEqual(c.r, 0x5B / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.g, 0x8D / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.b, 0xEF / 255.0, accuracy: 0.001)
        XCTAssertEqual(c.a, 1, accuracy: 0.001)
    }
    func test_eachPalette_hasNonNeutralAccents_andDistinctBase() {
        for p in AmbiancePalette.allCases {
            let c = p.colors
            XCTAssertNotEqual(c.base, c.accentPrimary)
            XCTAssertNotEqual(c.accentPrimary, c.accentSecondary)
            XCTAssertEqual(c.hairline.a, 0.14, accuracy: 0.001)   // neutre commun
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path /Users/spidersnake/Documents/Dev/FlowScribe/FlowScribeCore --filter AmbianceTests`
Expected: FAIL (cannot find `ambianceAnimates`, `AmbiancePalette`, …).

- [ ] **Step 3: Write the implementation**

```swift
// FlowScribeCore/Sources/FlowScribeCore/Ambiance.swift
import Foundation

public enum AmbiancePalette: String, CaseIterable, Sendable, Codable {
    case nuitBleue, auroreFroide, auroreDuale
}
public enum AmbianceIntensity: String, CaseIterable, Sendable, Codable {
    case discret, equilibre, showcase
}
public enum AmbianceSurface: Sendable { case onboarding, hud, appWindow }

public struct RGBA: Equatable, Sendable {
    public let r, g, b, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    /// hex 0xRRGGBB
    public init(hex: UInt32, a: Double = 1) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255,
                  Double(hex & 0xFF) / 255, a)
    }
}

/// Jeu de rôles FIXE : toute vue peut référencer n'importe quel rôle (cahier §6.1).
public struct PaletteColors: Sendable {
    public let base, baseTop: RGBA
    public let accentPrimary, accentSecondary, accentTertiary, accentQuaternary: RGBA
    public let warm, warmSecondary: RGBA
    public let hairline, textPrimary, textSecondary: RGBA
}

public extension AmbiancePalette {
    var colors: PaletteColors {
        let hairline = RGBA(1, 1, 1, 0.14)
        let textPrimary = RGBA(1, 1, 1, 0.92)
        let textSecondary = RGBA(1, 1, 1, 0.60)
        switch self {
        case .nuitBleue:
            let pr = RGBA(hex: 0x5B8DEF)
            return PaletteColors(base: RGBA(hex: 0x060A1A), baseTop: RGBA(hex: 0x0A1430),
                accentPrimary: pr, accentSecondary: RGBA(hex: 0x7C6CFF),
                accentTertiary: RGBA(hex: 0x3FE0D0), accentQuaternary: pr,
                warm: RGBA(hex: 0xFF8A5C), warmSecondary: RGBA(hex: 0xFF8A5C),
                hairline: hairline, textPrimary: textPrimary, textSecondary: textSecondary)
        case .auroreFroide:
            return PaletteColors(base: RGBA(hex: 0x040712), baseTop: RGBA(hex: 0x091126),
                accentPrimary: RGBA(hex: 0x3A7BFF), accentSecondary: RGBA(hex: 0x9A5CFF),
                accentTertiary: RGBA(hex: 0x2BE7B0), accentQuaternary: RGBA(hex: 0x18C2FF),
                warm: RGBA(hex: 0xFF7A4D), warmSecondary: RGBA(hex: 0xFF7A4D),
                hairline: hairline, textPrimary: textPrimary, textSecondary: textSecondary)
        case .auroreDuale:
            return PaletteColors(base: RGBA(hex: 0x040712), baseTop: RGBA(hex: 0x091126),
                accentPrimary: RGBA(hex: 0x3A7BFF), accentSecondary: RGBA(hex: 0x9A5CFF),
                accentTertiary: RGBA(hex: 0x2BE7B0), accentQuaternary: RGBA(hex: 0x18C2FF),
                warm: RGBA(hex: 0xFF5C8A), warmSecondary: RGBA(hex: 0xFFB23F),
                hairline: hairline, textPrimary: textPrimary, textSecondary: textSecondary)
        }
    }
}

/// Politique d'animation à point unique (cahier §4 + garde-fous).
public func ambianceAnimates(intensity: AmbianceIntensity, surface: AmbianceSurface,
                             reduceMotion: Bool, windowActive: Bool) -> Bool {
    if reduceMotion { return false }
    switch surface {
    case .hud:
        return true                                   // strands du HUD : toujours animés (hors reduce-motion)
    case .onboarding:
        return intensity != .discret
    case .appWindow:
        switch intensity {
        case .discret: return false
        case .equilibre: return windowActive          // pause si fenêtre inactive
        case .showcase: return true
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path /Users/spidersnake/Documents/Dev/FlowScribe/FlowScribeCore --filter AmbianceTests`
Expected: PASS (8 tests).

- [ ] **Step 5: Run the full core suite (no regressions)**

Run: `swift test --package-path /Users/spidersnake/Documents/Dev/FlowScribe/FlowScribeCore 2>&1 | grep -E "All tests|failure"`
Expected: `Executed N tests, with 0 failures` (N = 94 + 8 = 102).

- [ ] **Step 6: Commit**

```bash
R=/Users/spidersnake/Documents/Dev/FlowScribe
git -C "$R" add FlowScribeCore/Sources/FlowScribeCore/Ambiance.swift FlowScribeCore/Tests/FlowScribeCoreTests/AmbianceTests.swift
git -C "$R" commit -m "feat(ambiance): cœur testable — palettes + politique d'animation"
```

---

## Task 2: App brand layer (BrandPalette, Ambiance environment, settings persistence)

**Files:**
- Create: `FlowScribe/BrandPalette.swift`
- Modify: `FlowScribe/SettingsStore.swift` (add two persisted properties)
- Modify: `FlowScribe/FlowScribeApp.swift` (inject `\.ambiance`)

**Interfaces:**
- Consumes: Task 1 (`AmbiancePalette`, `AmbianceIntensity`, `AmbianceSurface`, `PaletteColors`, `ambianceAnimates`).
- Produces: `extension RGBA { var color: Color }`; `struct BrandPalette` (`init(_ : AmbiancePalette)`, `var base/baseTop/accentPrimary/accentSecondary/accentTertiary/accentQuaternary/warm/warmSecondary/hairline: Color`, `var auroraColors: [Color]`); `struct Ambiance` (`palette: BrandPalette`, `intensity: AmbianceIntensity`, `func animates(_:reduceMotion:windowActive:) -> Bool`); `EnvironmentValues.ambiance`; `var AmbiancePalette.title: String`; `var AmbianceIntensity.title: String`; `SettingsStore.ambiancePalette`, `SettingsStore.ambianceIntensity`.

- [ ] **Step 1: Create the brand layer file**

```swift
// FlowScribe/BrandPalette.swift
import SwiftUI
import FlowScribeCore

extension RGBA {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

/// Couleurs SwiftUI dérivées d'une palette (les rôles neutres restent neutres ; seuls les accents changent).
struct BrandPalette {
    let colors: PaletteColors
    init(_ p: AmbiancePalette) { colors = p.colors }
    var base: Color { colors.base.color }
    var baseTop: Color { colors.baseTop.color }
    var accentPrimary: Color { colors.accentPrimary.color }
    var accentSecondary: Color { colors.accentSecondary.color }
    var accentTertiary: Color { colors.accentTertiary.color }
    var accentQuaternary: Color { colors.accentQuaternary.color }
    var warm: Color { colors.warm.color }
    var warmSecondary: Color { colors.warmSecondary.color }
    var hairline: Color { colors.hairline.color }
    var auroraColors: [Color] { [accentPrimary, accentSecondary, accentTertiary, accentQuaternary] }
}

/// Valeur injectée dans l'environnement : palette résolue + politique d'animation.
struct Ambiance {
    var palette: BrandPalette
    var intensity: AmbianceIntensity
    func animates(_ surface: AmbianceSurface, reduceMotion: Bool, windowActive: Bool) -> Bool {
        ambianceAnimates(intensity: intensity, surface: surface,
                         reduceMotion: reduceMotion, windowActive: windowActive)
    }
}

private struct AmbianceKey: EnvironmentKey {
    static let defaultValue = Ambiance(palette: BrandPalette(.nuitBleue), intensity: .equilibre)
}
extension EnvironmentValues {
    var ambiance: Ambiance {
        get { self[AmbianceKey.self] }
        set { self[AmbianceKey.self] = newValue }
    }
}

// Libellés FR (l'UI vit dans l'app, pas dans le cœur).
extension AmbiancePalette {
    var title: String {
        switch self {
        case .nuitBleue: return "Nuit bleue"
        case .auroreFroide: return "Aurore froide"
        case .auroreDuale: return "Aurore duale"
        }
    }
}
extension AmbianceIntensity {
    var title: String {
        switch self {
        case .discret: return "Discret"
        case .equilibre: return "Équilibré"
        case .showcase: return "Showcase"
        }
    }
}
```

- [ ] **Step 2: Add persisted settings (mirror the existing `didSet`/defaults pattern)**

In `FlowScribe/SettingsStore.swift`, add these two properties next to `recordingWindowStyle` (after line 74):

```swift
    /// Palette du rebranding (pilote les accents : aurores, fils, halos).
    var ambiancePalette: AmbiancePalette {
        didSet { defaults.set(ambiancePalette.rawValue, forKey: "ambiancePalette") }
    }
    /// Intensité des effets animés du rebranding.
    var ambianceIntensity: AmbianceIntensity {
        didSet { defaults.set(ambianceIntensity.rawValue, forKey: "ambianceIntensity") }
    }
```

And in `init(secrets:)` (after the `recordingWindowStyle` line, ~line 107):

```swift
        self.ambiancePalette = AmbiancePalette(rawValue: defaults.string(forKey: "ambiancePalette") ?? "") ?? .nuitBleue
        self.ambianceIntensity = AmbianceIntensity(rawValue: defaults.string(forKey: "ambianceIntensity") ?? "") ?? .equilibre
```

- [ ] **Step 3: Inject `\.ambiance` at the app root**

In `FlowScribe/FlowScribeApp.swift`, in the `WindowGroup(id: "main")` `Group { … }`, add the environment after `.frame(minWidth: 720, minHeight: 480)` (line ~32), before `.task`:

```swift
            .frame(minWidth: 720, minHeight: 480)
            .environment(\.ambiance, Ambiance(palette: BrandPalette(settings.ambiancePalette),
                                              intensity: settings.ambianceIntensity))
            .task { await setup() }
```

(Reading `settings.ambiancePalette` here registers Observation → the whole window re-resolves the environment live when the palette/intensity change.)

- [ ] **Step 4: Build**

Run the Global-Constraints build command.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
R=/Users/spidersnake/Documents/Dev/FlowScribe
git -C "$R" add FlowScribe/BrandPalette.swift FlowScribe/SettingsStore.swift FlowScribe/FlowScribeApp.swift
git -C "$R" commit -m "feat(ambiance): couche brand SwiftUI + persistance réglages + injection environnement"
```

---

## Task 3: Réglages → section « Apparence »

**Files:**
- Modify: `FlowScribe/SettingsView.swift`

**Interfaces:**
- Consumes: Task 2 (`SettingsStore.ambiancePalette`/`ambianceIntensity`, `AmbiancePalette.title`, `AmbianceIntensity.title`). `SettingsView` already declares `@Bindable var settings: SettingsStore`.

- [ ] **Step 1: Add the Apparence section**

In `FlowScribe/SettingsView.swift`, add this `Section` immediately after the `Enregistrement` section (after its closing `} header: { Text("Enregistrement") }`, ~line 22):

```swift
            Section {
                Picker("Palette", selection: $settings.ambiancePalette) {
                    ForEach(AmbiancePalette.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Intensité des effets", selection: $settings.ambianceIntensity) {
                    ForEach(AmbianceIntensity.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } header: { Text("Apparence") } footer: {
                Text("La palette colore les effets (aurores, fils, halos). L'intensité règle leur animation ; « Réduire les animations » du système est toujours respecté.")
            }
```

(`AmbiancePalette`/`AmbianceIntensity` are `String` enums → `Hashable`, valid as `ForEach` id and `Picker` tag.)

- [ ] **Step 2: Build**

Run the build command. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Visual check**

Run the app: `open /Users/spidersnake/Documents/Dev/FlowScribe/build/Build/Products/Debug/FlowScribe.app`. Open Réglages → confirm the **Apparence** section shows two pickers; switching them persists across relaunch.

- [ ] **Step 4: Commit**

```bash
R=/Users/spidersnake/Documents/Dev/FlowScribe
git -C "$R" add FlowScribe/SettingsView.swift
git -C "$R" commit -m "feat(réglages): section Apparence (palette + intensité)"
```

---

## Task 4: GrainientBackground brick

**Files:**
- Create: `FlowScribe/GrainientBackground.swift`

**Interfaces:**
- Consumes: Task 2 (`EnvironmentValues.ambiance`, `BrandPalette`).
- Produces: `struct GrainientBackground: View` (reads `\.ambiance`, draws `baseTop→base` gradient + fixed grain overlay). Default = static grain (perf).

- [ ] **Step 1: Create the brick**

```swift
// FlowScribe/GrainientBackground.swift
import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

/// Socle commun « grainient » : dégradé profond (palette) + grain fin, mat et premium.
/// Le grain est une texture pré-rendue, tilée à faible opacité → coût quasi nul (statique).
struct GrainientBackground: View {
    @Environment(\.ambiance) private var ambiance

    var body: some View {
        let p = ambiance.palette
        LinearGradient(colors: [p.baseTop, p.base], startPoint: .top, endPoint: .bottom)
            .overlay(
                Image(nsImage: GrainTexture.shared)
                    .resizable(resizingMode: .tile)
                    .opacity(0.05)
                    .blendMode(.overlay)
                    .allowsHitTesting(false)
            )
            .ignoresSafeArea()
    }
}

/// Texture de bruit monochrome générée une fois (CIRandomGenerator).
enum GrainTexture {
    static let shared: NSImage = make(side: 180)
    private static func make(side: Int) -> NSImage {
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        let noise = CIFilter.randomGenerator().outputImage ?? CIImage(color: .gray)
        let mono = noise.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
        let rep = NSCIImageRep(ciImage: mono.cropped(to: rect))
        let img = NSImage(size: NSSize(width: side, height: side))
        img.addRepresentation(rep)
        return img
    }
}
```

- [ ] **Step 2: Apply to one screen to validate (Réglages)**

In `FlowScribe/SettingsView.swift`, after `.scrollContentBackground(.hidden)` (line ~69) add:

```swift
        .background(GrainientBackground())
```

- [ ] **Step 3: Build + visual check**

Build (`** BUILD SUCCEEDED **`), run, open Réglages: the background is a deep palette gradient with fine grain. Switch palette in Apparence → the gradient hue updates live.

- [ ] **Step 4: Commit**

```bash
R=/Users/spidersnake/Documents/Dev/FlowScribe
git -C "$R" add FlowScribe/GrainientBackground.swift FlowScribe/SettingsView.swift
git -C "$R" commit -m "feat(brand): GrainientBackground (socle dégradé + grain), appliqué aux Réglages"
```

---

## Task 5: Apply Grainient across surfaces + derive Theme accent from palette

**Files:**
- Modify: `FlowScribe/RootView.swift` (detail background), `FlowScribe/Theme.swift`

**Interfaces:**
- Consumes: Task 4 (`GrainientBackground`), Task 2 (`\.ambiance`).

- [ ] **Step 1: Replace the main detail background**

In `FlowScribe/RootView.swift`, in the `detail:` `ZStack`, replace `VisualEffectBackground(material: .sidebar).ignoresSafeArea()` (line ~31) with:

```swift
                GrainientBackground()
```

(The sidebar column keeps its native material — only the center adopts grainient.)

- [ ] **Step 2: Make `Theme.accent` follow the palette (minimal, non-breaking)**

`Theme.accent` is read by many views. Keep the static API but point it at the default palette's primary so non-environment call sites still look on-brand. In `FlowScribe/Theme.swift`, change:

```swift
    static let sky       = Color(red: 0.44, green: 0.64, blue: 0.86)
    static let accent    = sky
```
to:
```swift
    static let sky       = Color(red: 0.44, green: 0.64, blue: 0.86)
    /// Accent statique de repli (= palette par défaut). Les vues « brand » lisent plutôt `\.ambiance`.
    static let accent    = AmbiancePalette.nuitBleue.colors.accentPrimary.color
```
Add `import FlowScribeCore` at the top of `Theme.swift` if not present, and the `RGBA.color` accessor is from `BrandPalette.swift` (same target).

- [ ] **Step 3: Build + visual check**

Build (`** BUILD SUCCEEDED **`), run. Accueil / Modes / Fichiers / Corrections / Calibration / Réglages all sit on the grainient socle; the sidebar keeps its translucent material; detail sheets still readable.

- [ ] **Step 4: Commit**

```bash
R=/Users/spidersnake/Documents/Dev/FlowScribe
git -C "$R" add FlowScribe/RootView.swift FlowScribe/Theme.swift
git -C "$R" commit -m "feat(brand): socle grainient sur le centre de l'app + accent dérivé de la palette"
```

---

## Task 6: `.borderGlow()` modifier + apply to focus elements

**Files:**
- Create: `FlowScribe/BorderGlow.swift`
- Modify: `FlowScribe/HomeView.swift` (Dicter button + active mode chip), `FlowScribe/APIKeysPanel.swift` (editing row)

**Interfaces:**
- Consumes: Task 2 (`\.ambiance`).
- Produces: `extension View { func borderGlow(active: Bool, cornerRadius: CGFloat) -> some View }`.

- [ ] **Step 1: Create the modifier**

```swift
// FlowScribe/BorderGlow.swift
import SwiftUI
import FlowScribeCore

/// Contour lumineux animé (réf. Border Glow). S'éteint en statique si les animations sont coupées.
struct BorderGlow: ViewModifier {
    @Environment(\.ambiance) private var ambiance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    var active: Bool
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let animate = active && ambiance.animates(.appWindow, reduceMotion: reduceMotion,
                                                  windowActive: activeState != .inactive)
        content.overlay {
            if active {
                TimelineView(.animation(paused: !animate)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    let deg = animate ? (t * 60).truncatingRemainder(dividingBy: 360) : 0
                    let ring = ambiance.palette.auroraColors + [ambiance.palette.auroraColors.first ?? .white]
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(AngularGradient(colors: ring, center: .center,
                                                      angle: .degrees(deg)), lineWidth: 1.5)
                        .blur(radius: 0.6)
                }
                .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func borderGlow(active: Bool = true, cornerRadius: CGFloat = 12) -> some View {
        modifier(BorderGlow(active: active, cornerRadius: cornerRadius))
    }
}
```

- [ ] **Step 2: Apply to the Dicter button and active mode chip (HomeView)**

In `FlowScribe/HomeView.swift`, on the "Dicter" button (the `.buttonStyle(.glassProminent)` one, ~line 24) append:

```swift
                .borderGlow(cornerRadius: 10)
```

On the `modeChip`'s `Capsule` background label, append after `.background(Color.primary.opacity(0.06), in: Capsule())`:

```swift
            .borderGlow(active: true, cornerRadius: 20)
```

- [ ] **Step 3: Apply to the editing API-key row**

In `FlowScribe/APIKeysPanel.swift`, in `row(_:)`, change the row's `.background(...)` to add the glow only when this row is expanded. After the existing `.background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))` line, append:

```swift
        .borderGlow(active: isEditing, cornerRadius: 10)
```

- [ ] **Step 4: Build + visual check**

Build (`** BUILD SUCCEEDED **`), run. The Dicter button + active mode chip have a soft moving lit edge (Équilibré, window active); expanding an API-key row lights its border. Set intensity → Discret in Réglages: glows go static. Toggle system Reduce Motion: glows go static.

- [ ] **Step 5: Commit**

```bash
R=/Users/spidersnake/Documents/Dev/FlowScribe
git -C "$R" add FlowScribe/BorderGlow.swift FlowScribe/HomeView.swift FlowScribe/APIKeysPanel.swift
git -C "$R" commit -m "feat(brand): .borderGlow() + halos sur Dicter, mode actif, ligne de clé en édition"
```

---

## Task 7: AuroraView brick

**Files:**
- Create: `FlowScribe/AuroraView.swift`

**Interfaces:**
- Consumes: Task 2 (`\.ambiance`).
- Produces: `struct AuroraView: View` (`var surface: AmbianceSurface = .appWindow`) — animated `MeshGradient` of palette accents, heavily blurred, gated by `ambiance.animates`.

- [ ] **Step 1: Create the brick**

```swift
// FlowScribe/AuroraView.swift
import SwiftUI
import FlowScribeCore

/// Rubans d'aurore : MeshGradient 3×3 aux points internes animés, fortement flouté.
struct AuroraView: View {
    @Environment(\.ambiance) private var ambiance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    var surface: AmbianceSurface = .appWindow

    var body: some View {
        let animate = ambiance.animates(surface, reduceMotion: reduceMotion,
                                        windowActive: activeState != .inactive)
        let p = ambiance.palette
        TimelineView(.animation(paused: !animate)) { tl in
            let t = animate ? tl.date.timeIntervalSinceReferenceDate : 0
            MeshGradient(width: 3, height: 3, points: points(t), colors: colors(p))
                .blur(radius: 48)
        }
        .allowsHitTesting(false)
    }

    private func points(_ t: Double) -> [SIMD2<Float>] {
        func w(_ a: Double, _ b: Double) -> Float { Float(0.5 + a * 0.18 * sin(t * b)) }
        return [
            SIMD2(0, 0),            SIMD2(0.5, 0),          SIMD2(1, 0),
            SIMD2(0, 0.5),          SIMD2(w(1, 0.7), w(1, 0.9)), SIMD2(1, 0.5),
            SIMD2(0, 1),            SIMD2(0.5, 1),          SIMD2(1, 1),
        ]
    }
    private func colors(_ p: BrandPalette) -> [Color] {
        let a = p.auroraColors
        return [p.base, a[1].opacity(0.7), p.base,
                a[0].opacity(0.8), a[2].opacity(0.9), a[3].opacity(0.8),
                p.base, a[2].opacity(0.7), p.base]
    }
}
```

- [ ] **Step 2: Build the brick in isolation (temporary preview check)**

Build (`** BUILD SUCCEEDED **`). (Applied to surfaces in Tasks 10–11; this task just lands the reusable brick and confirms it compiles.)

- [ ] **Step 3: Commit**

```bash
R=/Users/spidersnake/Documents/Dev/FlowScribe
git -C "$R" add FlowScribe/AuroraView.swift
git -C "$R" commit -m "feat(brand): AuroraView (MeshGradient animé, gaté par l'intensité)"
```

---

## Task 8: SideRaysView brick

**Files:**
- Create: `FlowScribe/SideRaysView.swift`

**Interfaces:**
- Consumes: Task 2 (`\.ambiance`).
- Produces: `struct SideRaysView: View` (`var surface: AmbianceSurface = .onboarding`) — soft light beams from the top-leading edge, blurred, slow shimmer, gated.

- [ ] **Step 1: Create the brick**

```swift
// FlowScribe/SideRaysView.swift
import SwiftUI
import FlowScribeCore

/// Faisceaux de lumière depuis un bord (réf. Side Rays) : quelques cônes de gradient flous + shimmer lent.
struct SideRaysView: View {
    @Environment(\.ambiance) private var ambiance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    var surface: AmbianceSurface = .onboarding

    var body: some View {
        let animate = ambiance.animates(surface, reduceMotion: reduceMotion,
                                        windowActive: activeState != .inactive)
        let cols = ambiance.palette.auroraColors
        TimelineView(.animation(paused: !animate)) { tl in
            let t = animate ? tl.date.timeIntervalSinceReferenceDate : 0
            Canvas { ctx, size in
                let origin = CGPoint(x: size.width * 0.08, y: -size.height * 0.1)
                for i in 0..<4 {
                    let base = Double(i) * 18 - 10
                    let sweep = base + 6 * sin(t * 0.5 + Double(i))
                    let len = size.height * 1.4
                    let a = Angle(degrees: sweep).radians
                    let spread = 0.06
                    var path = Path()
                    path.move(to: origin)
                    path.addLine(to: CGPoint(x: origin.x + len * sin(a - spread), y: origin.y + len * cos(a - spread)))
                    path.addLine(to: CGPoint(x: origin.x + len * sin(a + spread), y: origin.y + len * cos(a + spread)))
                    path.closeSubpath()
                    let c = cols[i % cols.count].opacity(0.10 + 0.05 * sin(t + Double(i)))
                    ctx.fill(path, with: .color(c))
                }
            }
            .blur(radius: 30)
        }
        .allowsHitTesting(false)
    }
}
```

- [ ] **Step 2: Build**

Build (`** BUILD SUCCEEDED **`). (Applied in Task 10.)

- [ ] **Step 3: Commit**

```bash
R=/Users/spidersnake/Documents/Dev/FlowScribe
git -C "$R" add FlowScribe/SideRaysView.swift
git -C "$R" commit -m "feat(brand): SideRaysView (faisceaux flous gatés)"
```

---

## Task 9: StrandsView brick (generalized from the HUD)

**Files:**
- Create: `FlowScribe/StrandsView.swift`

**Interfaces:**
- Consumes: Task 2 (`\.ambiance`), Task 1 (`AmbianceSurface`).
- Produces: `struct StrandsView: View` (params: `lineCount: Int = 6`, `amplitude: Double = 0.5`, `speed: Double = 1`, `surface: AmbianceSurface = .appWindow`) — the flowing horizontal lines, palette-tinted, gated.

- [ ] **Step 1: Create the brick (same math as the HUD, parameterized + palette-tinted)**

```swift
// FlowScribe/StrandsView.swift
import SwiftUI
import FlowScribeCore

/// Fils lumineux qui ondulent (motif signature). Généralise le rendu du HUD pour un usage plein écran.
struct StrandsView: View {
    @Environment(\.ambiance) private var ambiance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    var lineCount: Int = 6
    var amplitude: Double = 0.5        // 0…1 (au repos : pas de micro, ondulation douce)
    var speed: Double = 1
    var surface: AmbianceSurface = .appWindow

    var body: some View {
        let animate = ambiance.animates(surface, reduceMotion: reduceMotion,
                                        windowActive: activeState != .inactive)
        let cols = ambiance.palette.auroraColors
        TimelineView(.animation(paused: !animate)) { tl in
            let t = animate ? tl.date.timeIntervalSinceReferenceDate * speed : 0
            Canvas { ctx, size in
                let w = Double(size.width), h = Double(size.height)
                let midY = h / 2, maxSwing = h * 0.42, steps = 96
                for j in 0..<lineCount {
                    let phase = Double(j) * 0.7
                    let dir: Double = (j % 2 == 0) ? 1 : -1
                    let freq = 1.6 + Double(j) * 0.18
                    let amp = maxSwing * (0.16 + 0.84 * amplitude) * (1.0 - 0.06 * Double(j))
                    let k1 = 2 * Double.pi * freq, k2 = Double.pi * freq
                    let travel1 = dir * t * 1.7 + phase, travel2 = (-dir) * t * 1.1 + phase * 1.3
                    var path = Path()
                    for s in 0...steps {
                        let xN = Double(s) / Double(steps)
                        let envelope = sin(Double.pi * xN)
                        let wave = sin(k1 * xN + travel1) + 0.35 * sin(k2 * xN + travel2)
                        let yOffset = envelope * amp * wave
                        let pt = CGPoint(x: CGFloat(xN * w), y: CGFloat(midY - yOffset))
                        if s == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                    }
                    let depth = Double(j) / Double(max(1, lineCount - 1))
                    let color = cols[j % cols.count].opacity((0.5 - 0.35 * depth))
                    ctx.stroke(path, with: .color(color), lineWidth: CGFloat(1.8 - 0.12 * Double(j)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
```

- [ ] **Step 2: Build**

Build (`** BUILD SUCCEEDED **`). (Used by onboarding/HUD next.)

- [ ] **Step 3: Commit**

```bash
R=/Users/spidersnake/Documents/Dev/FlowScribe
git -C "$R" add FlowScribe/StrandsView.swift
git -C "$R" commit -m "feat(brand): StrandsView (motif signature généralisé, palette-tinté, gaté)"
```

---

## Task 10: Onboarding hero refonte

**Files:**
- Modify: `FlowScribe/OnboardingView.swift`

**Interfaces:**
- Consumes: Task 4 (`GrainientBackground`), Task 7 (`AuroraView`), Task 8 (`SideRaysView`), Task 9 (`StrandsView`), Task 6 (`.borderGlow()`).

- [ ] **Step 1: Replace the flat background with the brand hero**

In `FlowScribe/OnboardingView.swift`, replace `.background(VisualEffectBackground(material: .sidebar).ignoresSafeArea())` (line ~24) with:

```swift
        .background {
            ZStack {
                GrainientBackground()
                AuroraView(surface: .onboarding).opacity(0.9)
                SideRaysView(surface: .onboarding)
                StrandsView(lineCount: 7, amplitude: 0.35, speed: 0.6, surface: .onboarding)
                    .opacity(0.5)
            }
            .ignoresSafeArea()
        }
```

- [ ] **Step 2: Give the permission cards a lit edge**

In the `row(...)` builder, after `.background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))` (line ~102) append:

```swift
        .borderGlow(active: granted, cornerRadius: 12)
```

(A permission lights up once granted — a small reward moment.)

- [ ] **Step 3: Build + visual check**

Build (`** BUILD SUCCEEDED **`), run with onboarding shown (temporarily set `hasSeenOnboarding=false` by deleting the key: `defaults delete cloud.spidersnake.FlowScribe hasSeenOnboarding` — adjust to the app's bundle id — or run a fresh container). Confirm the « waouh » hero: grainient + drifting aurora + side rays + gentle strands, with the permission steps legible on top. Granting a permission lights its card edge.

- [ ] **Step 4: Commit**

```bash
R=/Users/spidersnake/Documents/Dev/FlowScribe
git -C "$R" add FlowScribe/OnboardingView.swift
git -C "$R" commit -m "feat(onboarding): héros « Voix → Lumière » (grainient + aurora + rays + strands)"
```

---

## Task 11: HUD palette alignment + recording glow

**Files:**
- Modify: `FlowScribe/HUDWaveform.swift`, `FlowScribe/ClassicHUDView.swift`, `FlowScribe/LiveHUDView.swift`, `FlowScribe/RecordingHUD.swift`, `FlowScribe/FlowScribeApp.swift`

**Interfaces:**
- Consumes: Task 2 (`BrandPalette`, `\.ambiance`). **Constraint:** the HUD is hosted in an `NSPanel`/`NSHostingView` outside the main-window SwiftUI tree, so the environment must be **explicitly injected** on the hosting root view.

- [ ] **Step 1: Inject `\.ambiance` into the HUD hosting views**

In `FlowScribe/RecordingHUD.swift`, add a stored palette/intensity and set the environment on the hosted views. Add a property:

```swift
    var ambiance = Ambiance(palette: BrandPalette(.nuitBleue), intensity: .equilibre)
```
and change `clearHosting(AnyView(ClassicHUDView(model: model)))` / `clearHosting(AnyView(LiveHUDView(model: model)))` to inject the environment:

```swift
                panel.contentView = clearHosting(AnyView(ClassicHUDView(model: model).environment(\.ambiance, ambiance)))
```
```swift
                panel.contentView = clearHosting(AnyView(LiveHUDView(model: model).environment(\.ambiance, ambiance)))
```

- [ ] **Step 2: Keep the HUD's `ambiance` in sync with settings**

In `FlowScribe/FlowScribeApp.swift` `setup()`, after `hud.style = settings.recordingWindowStyle` (line ~120) add:

```swift
        hud.ambiance = Ambiance(palette: BrandPalette(settings.ambiancePalette), intensity: settings.ambianceIntensity)
```
and in the `settings.onChange = { … }` closure (line ~147), alongside `hud.style = settings.recordingWindowStyle`, add:

```swift
            hud.ambiance = Ambiance(palette: BrandPalette(settings.ambiancePalette), intensity: settings.ambianceIntensity)
```

- [ ] **Step 3: Tint the strands with the palette**

In `FlowScribe/HUDWaveform.swift`, change `lineColor(index:of:level:)` to accept palette accents. Replace its body so the grayscale becomes palette-tinted while keeping the same opacity ramp:

```swift
    /// Lignes du maillage (HUD Classic), teintées par la palette de marque.
    static func lineColor(index j: Int, of count: Int, level: Double, accents: [Color]) -> Color {
        let depth = Double(j) / Double(max(1, count - 1))
        let opacity = (0.55 - 0.40 * depth) * (0.55 + 0.45 * level)
        return accents[j % accents.count].opacity(opacity)
    }
```

In `FlowScribe/ClassicHUDView.swift`, read `@Environment(\.ambiance) private var ambiance` and pass `accents: ambiance.palette.auroraColors` into the `lineColor` call. In `FlowScribe/LiveHUDView.swift`, similarly tint `HUDWaveform.barColor` — change `barColor(frac:)` callers to a palette accent (e.g., `ambiance.palette.accentPrimary.opacity(...)`), reading `@Environment(\.ambiance)` in `LiveHUDView`.

- [ ] **Step 4: Add a recording border glow to the Classic panel**

In `FlowScribe/ClassicHUDView.swift`, on the outer `VStack` (after `.shadow(...)`, line ~23) append:

```swift
        .borderGlow(active: model.state == .recording, cornerRadius: 18)
```

- [ ] **Step 5: Build + visual check**

Build (`** BUILD SUCCEEDED **`), run, record. The HUD strands take the palette colors; the Classic panel gets a soft moving lit edge while recording. Verify the recent HUD fixes still hold (no visible corners, smooth, animates during menus). Switch palette in Réglages → next HUD shows new colors.

- [ ] **Step 6: Commit**

```bash
R=/Users/spidersnake/Documents/Dev/FlowScribe
git -C "$R" add FlowScribe/HUDWaveform.swift FlowScribe/ClassicHUDView.swift FlowScribe/LiveHUDView.swift FlowScribe/RecordingHUD.swift FlowScribe/FlowScribeApp.swift
git -C "$R" commit -m "feat(hud): strands teintés par la palette + halo d'enregistrement (environnement injecté dans le NSHostingView)"
```

---

## Task 12: Home aurora-behind-title, detail warm error, sidebar tint

**Files:**
- Modify: `FlowScribe/HomeView.swift`, `FlowScribe/TranscriptionDetailView.swift`, `FlowScribe/RootView.swift`

**Interfaces:**
- Consumes: Task 7 (`AuroraView`), Task 2 (`\.ambiance`).

- [ ] **Step 1: Faint aurora behind the « Historique » title (Home)**

In `FlowScribe/HomeView.swift`, wrap the header `HStack` (the one with "Historique") in a `ZStack` with a low-opacity aurora confined to the top:

```swift
            ZStack(alignment: .top) {
                AuroraView(surface: .appWindow).frame(height: 120).opacity(0.35).allowsHitTesting(false)
                HStack(alignment: .center, spacing: 12) {
                    Text("Historique").font(.system(size: 22, weight: .bold))
                    Spacer()
                    modeChip
                    Button(action: onToggleRecord) { Label("Dicter", systemImage: "mic.fill") }
                        .buttonStyle(.glassProminent).help("Dicter (⌥Espace)").borderGlow(cornerRadius: 10)
                }
            }
```

- [ ] **Step 2: Tie the detail error banner to the palette warm accent**

In `FlowScribe/TranscriptionDetailView.swift`, read `@Environment(\.ambiance) private var ambiance` and change the error banner's `.orange` usages (icon `foregroundStyle` and the `Color.orange.opacity(0.12)` background) to `ambiance.palette.warm`:

```swift
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(ambiance.palette.warm)
```
```swift
                .background(ambiance.palette.warm.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
```

(Do the same for the Home card's failed indicator in `FlowScribe/HomeView.swift`: replace `Color.orange` with `ambiance.palette.warm`, reading `@Environment(\.ambiance)` in `HomeView`.)

- [ ] **Step 3: Tint the sidebar material with the palette**

In `FlowScribe/RootView.swift`, overlay a faint palette tint on the sidebar column. On the `SidebarView(...)` add:

```swift
                .background(ambiance.palette.base.opacity(0.25))
```
reading `@Environment(\.ambiance) private var ambiance` in `RootView`. (The native `.sidebar` material remains underneath via the column's default; this only nudges the hue.)

- [ ] **Step 4: Build + visual check**

Build (`** BUILD SUCCEEDED **`), run. A faint aurora glows behind « Historique »; failed records/banners use the palette's warm tone (e.g., magenta in « Aurore duale »); the sidebar carries a subtle palette tint.

- [ ] **Step 5: Commit**

```bash
R=/Users/spidersnake/Documents/Dev/FlowScribe
git -C "$R" add FlowScribe/HomeView.swift FlowScribe/TranscriptionDetailView.swift FlowScribe/RootView.swift
git -C "$R" commit -m "feat(brand): aurora derrière le titre d'accueil, erreurs sur l'accent chaud, sidebar teintée"
```

---

## Task 13: Performance / reduce-motion / window-active verification pass

**Files:**
- Modify (only if a gap is found): any brick missing `TimelineView(.animation(paused:))` gating.

**Interfaces:**
- Consumes: all prior tasks.

- [ ] **Step 1: Audit every TimelineView is gated**

Run: `grep -rn "TimelineView(.animation" /Users/spidersnake/Documents/Dev/FlowScribe/FlowScribe/`
Expected: every match uses `.animation(paused: !animate)` where `animate` comes from `ambiance.animates(...)` — **except** `ClassicHUDView`/`LiveHUDView`'s own waveform `TimelineView` (HUD strands), which the spec says always animate while recording. Confirm no app-window brick animates unconditionally.

- [ ] **Step 2: Manual matrix check**

Run the app. For each combination, confirm behavior:
- Réglages → Intensité = **Discret**: accueil/HUD-panel glow static; HUD strands still animate while recording.
- Intensité = **Équilibré**, focus another app: main-window aurora/glows pause; return focus → resume.
- Intensité = **Showcase**: main-window effects animate even when unfocused.
- System Settings → Accessibility → **Reduce Motion** ON: everything static everywhere.
- App in background (window closed): no effect runs (open Activity Monitor → FlowScribe CPU ≈ 0 at idle).

- [ ] **Step 3: Build + full core suite**

Build (`** BUILD SUCCEEDED **`) and `swift test --package-path /Users/spidersnake/Documents/Dev/FlowScribe/FlowScribeCore 2>&1 | grep -E "All tests|failure"` → `0 failures`.

- [ ] **Step 4: Commit (if any gating gap was fixed; otherwise skip)**

```bash
R=/Users/spidersnake/Documents/Dev/FlowScribe
git -C "$R" add -A
git -C "$R" commit -m "fix(perf): gating animations (intensité × reduce-motion × fenêtre active) — passe de vérification"
```

---

## Self-Review (run by the plan author)

**Spec coverage** (spec §): §2 effect set → Tasks 4,6,7,8,9 (Gradient Blinds absent ✓). §3 palettes → Task 1 (`colors`) + Task 2 (`BrandPalette`) + Task 3 (picker). §4 intensity → Task 1 (`ambianceAnimates`) + Task 3 (picker) + gating in every brick + Task 13. §5 surfaces → onboarding (10), HUD (11), home/detail/sidebar (12), settings (3,4), API keys (6). §6 architecture → Tasks 1–2 (core/app split, environment, `animates`), bricks 4/6/7/8/9. §7 perf/accessibility → gating in each brick + Task 13. §8 testable units → Task 1 tests (palette mapping + `animates` truth table). §9 build order → Tasks grouped Phase 1 (1–3), 2 (4–5), 3 (6–9), 4 (10), 5 (11–13). §10 out-of-scope (logo, blinds, light mode) → not implemented ✓. §11 risks → no exclusive Metal dependency (grain via CIRandomGenerator; aurora via MeshGradient) ✓.

**Placeholder scan:** No TBD/TODO; every code step shows complete code; commands are concrete.

**Type consistency:** `ambianceAnimates(intensity:surface:reduceMotion:windowActive:)` used identically in Task 1 and in every brick. `BrandPalette.auroraColors` used by BorderGlow/Aurora/Strands/HUD. `Ambiance.animates(_:reduceMotion:windowActive:)` signature consistent. `HUDWaveform.lineColor(index:of:level:accents:)` updated signature matches its Task-11 caller. `\.ambiance` environment key consistent (Task 2 defines, all bricks read).

**Note on persistence test:** `ambiancePalette`/`ambianceIntensity` persistence is verified by build + the Task-3 visual relaunch check (the app has no app-level XCTest target; UserDefaults round-trip isn't unit-tested in-process, matching the existing `recordingWindowStyle` pattern which is likewise not unit-tested).

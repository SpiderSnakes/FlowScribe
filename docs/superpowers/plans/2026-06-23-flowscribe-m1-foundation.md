# FlowScribe — M1 Fondation — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Une app macOS où Option+Espace (tap) enregistre la voix, la transcrit avec Apple `SpeechAnalyzer` (local, fichier), puis colle le texte au curseur + presse-papier — zéro config, sans clé API.

**Architecture:** Logique testable isolée dans un package SPM local `FlowScribeCore` (lancé via `swift test`), pilotant des protocoles (`TranscriptionEngine`, `AudioRecorder`, `TextOutput`) ; une fine coquille app SwiftUI (projet Xcode généré par XcodeGen) câble le hotkey, le HUD flottant, les permissions et la présence Dock + barre de menus.

**Tech Stack:** Swift 6, SwiftUI + AppKit, package SPM local, XcodeGen, `Speech` (SpeechAnalyzer/SpeechTranscriber), AVFoundation (AVAudioEngine), `KeyboardShortcuts` (Sindre Sorhus), XCTest.

## Global Constraints

- Plateforme : **macOS 26.0+**, **Apple Silicon (arm64)** uniquement.
- Langage : **Swift 6**, concurrence stricte (`@MainActor` pour l'UI et les contrôleurs).
- M1 **n'utilise aucune clé API** ni réseau : seul le moteur Apple local existe.
- Bundle identifier : `cloud.spidersnake.FlowScribe`.
- Toute la logique métier vit dans `FlowScribeCore` et se teste via `swift test`. L'app n'a que du câblage.
- Les usage descriptions de permissions vivent dans `FlowScribe/Info.plist` (généré par XcodeGen).
- Commits fréquents : un commit par tâche minimum, message en français, trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Push sur `origin main` après chaque tâche.

---

## Structure de fichiers (verrouillée avant les tâches)

```
FlowScribe/                      (racine repo, déjà un dépôt git)
├── project.yml                  XcodeGen : définit l'app + dépendances
├── FlowScribeCore/              package SPM local (logique testable)
│   ├── Package.swift
│   ├── Sources/FlowScribeCore/
│   │   ├── Models.swift              TranscriptResult, EngineCapabilities, AudioRecording
│   │   ├── TranscriptionEngine.swift protocole + MockEngine
│   │   ├── AppleSpeechEngine.swift   impl Apple (SpeechAnalyzer, fichier)
│   │   ├── AudioRecorder.swift       protocole + MicrophoneRecorder (AVAudioEngine → CAF)
│   │   ├── PressClassifier.swift     logique pure tap vs maintien
│   │   ├── TextOutput.swift          protocole + SystemTextOutput (presse-papier + Cmd+V)
│   │   └── DictationController.swift  machine à états orchestrant tout
│   └── Tests/FlowScribeCoreTests/
│       ├── PressClassifierTests.swift
│       ├── DictationControllerTests.swift
│       ├── TranscriptionEngineTests.swift
│       └── TextOutputTests.swift
└── FlowScribe/                  (sources app)
    ├── Info.plist               (généré par XcodeGen via project.yml)
    ├── FlowScribeApp.swift       @main, Dock + barre de menus + permissions
    ├── HotkeyBridge.swift        câble KeyboardShortcuts → DictationController
    ├── RecordingHUD.swift        NSPanel flottant + vue SwiftUI
    └── Permissions.swift         demande micro + reconnaissance vocale
```

**Frontières :** `FlowScribeCore` ne dépend que de frameworks système (Foundation, Speech, AVFoundation, AppKit pour `NSPasteboard`/`CGEvent`). L'app dépend de `FlowScribeCore` + `KeyboardShortcuts`. Aucune logique métier dans l'app.

---

### Task 1: Scaffolding — package core + projet XcodeGen qui build et teste

**Files:**
- Create: `FlowScribeCore/Package.swift`
- Create: `FlowScribeCore/Sources/FlowScribeCore/Models.swift`
- Create: `FlowScribeCore/Tests/FlowScribeCoreTests/SmokeTests.swift`
- Create: `project.yml`
- Create: `FlowScribe/FlowScribeApp.swift`

**Interfaces:**
- Produces: package `FlowScribeCore` compilable + cible app Xcode `FlowScribe`.

- [ ] **Step 1: Installer XcodeGen (si absent)**

Run: `which xcodegen || brew install xcodegen`
Expected: chemin affiché, ou installation réussie.

- [ ] **Step 2: Écrire `FlowScribeCore/Package.swift`**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FlowScribeCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FlowScribeCore", targets: ["FlowScribeCore"])
    ],
    targets: [
        .target(name: "FlowScribeCore"),
        .testTarget(name: "FlowScribeCoreTests", dependencies: ["FlowScribeCore"])
    ]
)
```
> `.v26` exige `swift-tools-version: 6.2` (introduit là) ; le toolchain Swift 6.4 le fournit. Si jamais indisponible, replier sur `.macOS(.v15)` + `@available(macOS 26.0, *)`.

- [ ] **Step 3: Écrire un modèle minimal `Models.swift`**

```swift
import Foundation

/// Résultat d'un segment de transcription (utilisé en streaming plus tard).
public struct TranscriptResult: Equatable, Sendable {
    public let text: String
    public let isFinal: Bool
    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

/// Capacités déclarées par un moteur de transcription.
public struct EngineCapabilities: Equatable, Sendable {
    public let supportsStreaming: Bool
    public let supportsKeyterms: Bool
    public let isLocal: Bool
    public init(supportsStreaming: Bool, supportsKeyterms: Bool, isLocal: Bool) {
        self.supportsStreaming = supportsStreaming
        self.supportsKeyterms = supportsKeyterms
        self.isLocal = isLocal
    }
}

/// Un enregistrement audio sur disque.
public struct AudioRecording: Equatable, Sendable {
    public let url: URL
    public let duration: TimeInterval?
    public init(url: URL, duration: TimeInterval?) {
        self.url = url
        self.duration = duration
    }
}
```

- [ ] **Step 4: Écrire `SmokeTests.swift`**

```swift
import XCTest
@testable import FlowScribeCore

final class SmokeTests: XCTestCase {
    func test_capabilities_storesValues() {
        let caps = EngineCapabilities(supportsStreaming: true, supportsKeyterms: false, isLocal: true)
        XCTAssertTrue(caps.supportsStreaming)
        XCTAssertFalse(caps.supportsKeyterms)
        XCTAssertTrue(caps.isLocal)
    }
}
```

- [ ] **Step 5: Lancer les tests du package — doit passer**

Run: `cd FlowScribeCore && swift test`
Expected: PASS (1 test).

- [ ] **Step 6: Écrire `project.yml` (XcodeGen)**

```yaml
name: FlowScribe
options:
  bundleIdPrefix: cloud.spidersnake
  deploymentTarget:
    macOS: "26.0"
  createIntermediateGroups: true
settings:
  base:
    SWIFT_VERSION: "6.0"
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    CODE_SIGN_STYLE: Manual
    CODE_SIGN_IDENTITY: "Developer ID Application"
    DEVELOPMENT_TEAM: "Y8XLVL2758"
    ARCHS: arm64
packages:
  FlowScribeCore:
    path: FlowScribeCore
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: "2.0.0"
targets:
  FlowScribe:
    type: application
    platform: macOS
    sources:
      - path: FlowScribe
    dependencies:
      - package: FlowScribeCore
      - package: KeyboardShortcuts
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: cloud.spidersnake.FlowScribe
        ENABLE_HARDENED_RUNTIME: YES
        INFOPLIST_KEY_LSUIElement: NO
    info:
      path: FlowScribe/Info.plist
      properties:
        CFBundleDisplayName: FlowScribe
        LSMinimumSystemVersion: "26.0"
        NSMicrophoneUsageDescription: "FlowScribe a besoin du micro pour transcrire votre voix."
        NSSpeechRecognitionUsageDescription: "FlowScribe utilise la reconnaissance vocale locale de macOS pour transcrire vos dictées."
```

- [ ] **Step 7: Écrire un point d'entrée app minimal `FlowScribe/FlowScribeApp.swift`**

```swift
import SwiftUI

@main
struct FlowScribeApp: App {
    var body: some Scene {
        WindowGroup("FlowScribe") {
            Text("FlowScribe")
                .frame(width: 360, height: 200)
        }
    }
}
```

- [ ] **Step 8: Générer le projet et builder l'app**

Run: `xcodegen generate && xcodebuild -project FlowScribe.xcodeproj -scheme FlowScribe -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 9: Ignorer le .xcodeproj généré et committer**

```bash
echo "FlowScribe.xcodeproj/" >> .gitignore
git add .gitignore project.yml FlowScribeCore FlowScribe
git commit -m "feat(m1): scaffolding package core + app XcodeGen

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push
```

---

### Task 2: Protocole `TranscriptionEngine` + moteur factice

**Files:**
- Create: `FlowScribeCore/Sources/FlowScribeCore/TranscriptionEngine.swift`
- Test: `FlowScribeCore/Tests/FlowScribeCoreTests/TranscriptionEngineTests.swift`

**Interfaces:**
- Produces: `protocol TranscriptionEngine { var id: String { get }; var capabilities: EngineCapabilities { get }; func transcribeFile(at url: URL, locale: Locale) async throws -> String }` ; `final class MockEngine: TranscriptionEngine`.

- [ ] **Step 1: Écrire le test (échoue)**

```swift
import XCTest
@testable import FlowScribeCore

final class TranscriptionEngineTests: XCTestCase {
    func test_mockEngine_returnsConfiguredText() async throws {
        let engine = MockEngine(id: "mock", result: "bonjour le monde")
        let text = try await engine.transcribeFile(at: URL(filePath: "/tmp/x.caf"), locale: Locale(identifier: "fr-FR"))
        XCTAssertEqual(text, "bonjour le monde")
        XCTAssertTrue(engine.capabilities.isLocal)
    }
}
```

- [ ] **Step 2: Lancer — doit échouer**

Run: `cd FlowScribeCore && swift test --filter TranscriptionEngineTests`
Expected: FAIL (MockEngine / TranscriptionEngine introuvable).

- [ ] **Step 3: Écrire `TranscriptionEngine.swift`**

```swift
import Foundation

public protocol TranscriptionEngine: Sendable {
    var id: String { get }
    var capabilities: EngineCapabilities { get }
    /// Transcrit un fichier audio déjà enregistré sur disque.
    func transcribeFile(at url: URL, locale: Locale) async throws -> String
}

/// Moteur factice pour les tests : renvoie un texte fixe.
public final class MockEngine: TranscriptionEngine {
    public let id: String
    public let capabilities: EngineCapabilities
    private let result: String
    public init(id: String, result: String) {
        self.id = id
        self.result = result
        self.capabilities = EngineCapabilities(supportsStreaming: false, supportsKeyterms: false, isLocal: true)
    }
    public func transcribeFile(at url: URL, locale: Locale) async throws -> String {
        result
    }
}
```

- [ ] **Step 4: Lancer — doit passer**

Run: `cd FlowScribeCore && swift test --filter TranscriptionEngineTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add FlowScribeCore && git commit -m "feat(m1): protocole TranscriptionEngine + MockEngine

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && git push
```

---

### Task 3: Classifieur tap vs maintien (logique pure)

**Files:**
- Create: `FlowScribeCore/Sources/FlowScribeCore/PressClassifier.swift`
- Test: `FlowScribeCore/Tests/FlowScribeCoreTests/PressClassifierTests.swift`

**Interfaces:**
- Produces: `enum PressKind { case tap, hold }` ; `enum PressClassifier { static func classify(pressDuration: TimeInterval, holdThreshold: TimeInterval) -> PressKind }`.

- [ ] **Step 1: Écrire le test (échoue)**

```swift
import XCTest
@testable import FlowScribeCore

final class PressClassifierTests: XCTestCase {
    func test_shortPress_isTap() {
        XCTAssertEqual(PressClassifier.classify(pressDuration: 0.10, holdThreshold: 0.25), .tap)
    }
    func test_longPress_isHold() {
        XCTAssertEqual(PressClassifier.classify(pressDuration: 0.80, holdThreshold: 0.25), .hold)
    }
    func test_exactlyAtThreshold_isHold() {
        XCTAssertEqual(PressClassifier.classify(pressDuration: 0.25, holdThreshold: 0.25), .hold)
    }
}
```

- [ ] **Step 2: Lancer — doit échouer**

Run: `cd FlowScribeCore && swift test --filter PressClassifierTests`
Expected: FAIL.

- [ ] **Step 3: Écrire `PressClassifier.swift`**

```swift
import Foundation

public enum PressKind: Equatable, Sendable { case tap, hold }

public enum PressClassifier {
    /// Un appui >= seuil est un "maintien" (push-to-talk), sinon un "tap" (bascule).
    public static func classify(pressDuration: TimeInterval, holdThreshold: TimeInterval) -> PressKind {
        pressDuration >= holdThreshold ? .hold : .tap
    }
}
```

- [ ] **Step 4: Lancer — doit passer**

Run: `cd FlowScribeCore && swift test --filter PressClassifierTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add FlowScribeCore && git commit -m "feat(m1): classifieur tap/maintien (pur)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && git push
```

---

### Task 4: `DictationController` — machine à états (tap + maintien)

**Files:**
- Create: `FlowScribeCore/Sources/FlowScribeCore/AudioRecorder.swift` (protocole seulement ici)
- Create: `FlowScribeCore/Sources/FlowScribeCore/TextOutput.swift` (protocole seulement ici)
- Create: `FlowScribeCore/Sources/FlowScribeCore/DictationController.swift`
- Test: `FlowScribeCore/Tests/FlowScribeCoreTests/DictationControllerTests.swift`

**Interfaces:**
- Consumes: `TranscriptionEngine` (Task 2), `PressKind` (Task 3).
- Produces:
  - `protocol AudioRecorder: Sendable { func start() throws; func stop() async -> AudioRecording }`
  - `protocol TextOutput: Sendable { func deliver(_ text: String) }`
  - `enum DictationState { case idle, recording, transcribing }`
  - `@MainActor final class DictationController` avec `pressDown()`, `pressUp(kind: PressKind) async`, `var state`, `var lastTranscript: String?`.

- [ ] **Step 1: Écrire le test (échoue)**

```swift
import XCTest
@testable import FlowScribeCore

@MainActor
final class DictationControllerTests: XCTestCase {

    final class SpyRecorder: AudioRecorder {
        nonisolated(unsafe) var startCount = 0
        nonisolated(unsafe) var stopCount = 0
        func start() throws { startCount += 1 }
        func stop() async -> AudioRecording { stopCount += 1; return AudioRecording(url: URL(filePath: "/tmp/a.caf"), duration: 1) }
    }
    final class SpyOutput: TextOutput {
        nonisolated(unsafe) var delivered: [String] = []
        func deliver(_ text: String) { delivered.append(text) }
    }

    func makeController() -> (DictationController, SpyRecorder, SpyOutput) {
        let rec = SpyRecorder(); let out = SpyOutput()
        let engine = MockEngine(id: "mock", result: "salut")
        let c = DictationController(recorder: rec, engine: engine, output: out, locale: Locale(identifier: "fr-FR"))
        return (c, rec, out)
    }

    func test_tap_startsThenStops_andDelivers() async {
        let (c, rec, out) = makeController()
        // 1er tap : démarre
        c.pressDown(); await c.pressUp(kind: .tap)
        XCTAssertEqual(c.state, .recording)
        XCTAssertEqual(rec.startCount, 1)
        // 2e tap : arrête + transcrit + livre
        c.pressDown(); await c.pressUp(kind: .tap)
        XCTAssertEqual(rec.stopCount, 1)
        XCTAssertEqual(out.delivered, ["salut"])
        XCTAssertEqual(c.state, .idle)
    }

    func test_hold_recordsWhileHeld_thenStopsOnRelease() async {
        let (c, rec, out) = makeController()
        c.pressDown()                      // keyDown : démarre
        XCTAssertEqual(rec.startCount, 1)
        XCTAssertEqual(c.state, .recording)
        await c.pressUp(kind: .hold)        // keyUp long : arrête + livre
        XCTAssertEqual(rec.stopCount, 1)
        XCTAssertEqual(out.delivered, ["salut"])
        XCTAssertEqual(c.state, .idle)
    }
}
```

- [ ] **Step 2: Lancer — doit échouer**

Run: `cd FlowScribeCore && swift test --filter DictationControllerTests`
Expected: FAIL.

- [ ] **Step 3: Écrire les protocoles `AudioRecorder.swift` et `TextOutput.swift`**

`AudioRecorder.swift` :
```swift
import Foundation

public protocol AudioRecorder: Sendable {
    func start() throws
    func stop() async -> AudioRecording
}
```

`TextOutput.swift` :
```swift
import Foundation

public protocol TextOutput: Sendable {
    func deliver(_ text: String)
}
```

- [ ] **Step 4: Écrire `DictationController.swift`**

```swift
import Foundation

public enum DictationState: Equatable, Sendable { case idle, recording, transcribing }

@MainActor
public final class DictationController {
    public private(set) var state: DictationState = .idle
    public private(set) var lastTranscript: String?

    private let recorder: AudioRecorder
    private let engine: TranscriptionEngine
    private let output: TextOutput
    private let locale: Locale

    /// True si l'appui en cours a lui-même démarré l'enregistrement (sert au comportement du tap).
    private var pressStartedRecording = false

    public init(recorder: AudioRecorder, engine: TranscriptionEngine, output: TextOutput, locale: Locale) {
        self.recorder = recorder
        self.engine = engine
        self.output = output
        self.locale = locale
    }

    /// Appel sur keyDown du hotkey.
    public func pressDown() {
        if state == .idle {
            do {
                try recorder.start()
                state = .recording
                pressStartedRecording = true
            } catch {
                state = .idle
            }
        } else {
            pressStartedRecording = false
        }
    }

    /// Appel sur keyUp du hotkey, avec le type d'appui classifié.
    public func pressUp(kind: PressKind) async {
        switch kind {
        case .hold:
            // Push-to-talk : on relâche -> on arrête toujours.
            await finishRecording()
        case .tap:
            // Bascule : si ce tap vient de démarrer, on laisse tourner ; sinon il arrête.
            if pressStartedRecording {
                return
            } else {
                await finishRecording()
            }
        }
    }

    private func finishRecording() async {
        guard state == .recording else { return }
        let recording = await recorder.stop()
        state = .transcribing
        do {
            let text = try await engine.transcribeFile(at: recording.url, locale: locale)
            lastTranscript = text
            output.deliver(text)
        } catch {
            lastTranscript = nil
        }
        state = .idle
    }
}
```

- [ ] **Step 5: Lancer — doit passer**

Run: `cd FlowScribeCore && swift test --filter DictationControllerTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add FlowScribeCore && git commit -m "feat(m1): DictationController (machine à états tap + maintien)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && git push
```

---

### Task 5: `SystemTextOutput` — presse-papier (testé) + collage Cmd+V

**Files:**
- Modify: `FlowScribeCore/Sources/FlowScribeCore/TextOutput.swift`
- Test: `FlowScribeCore/Tests/FlowScribeCoreTests/TextOutputTests.swift`

**Interfaces:**
- Produces: `final class SystemTextOutput: TextOutput` ; helper testable `enum Clipboard { static func write(_ text: String, to pasteboard: NSPasteboard) }`.

- [ ] **Step 1: Écrire le test (échoue) — on teste l'écriture presse-papier sur un pasteboard nommé isolé**

```swift
import XCTest
import AppKit
@testable import FlowScribeCore

final class TextOutputTests: XCTestCase {
    func test_clipboard_writesString() {
        let pb = NSPasteboard(name: NSPasteboard.Name("FlowScribeTest"))
        pb.clearContents()
        Clipboard.write("café été", to: pb)
        XCTAssertEqual(pb.string(forType: .string), "café été")
    }
}
```

- [ ] **Step 2: Lancer — doit échouer**

Run: `cd FlowScribeCore && swift test --filter TextOutputTests`
Expected: FAIL (Clipboard introuvable).

- [ ] **Step 3: Compléter `TextOutput.swift`**

```swift
import Foundation
import AppKit

public protocol TextOutput: Sendable {
    func deliver(_ text: String)
}

/// Écriture presse-papier isolée pour être testable.
public enum Clipboard {
    public static func write(_ text: String, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

/// Sortie réelle : copie dans le presse-papier système puis simule Cmd+V.
public final class SystemTextOutput: TextOutput {
    public init() {}

    public func deliver(_ text: String) {
        Clipboard.write(text, to: .general)
        Self.simulatePaste()
    }

    /// Simule un Cmd+V via CGEvent (nécessite la permission Accessibilité).
    private static func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09 // 'v'
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 4: Lancer — doit passer**

Run: `cd FlowScribeCore && swift test --filter TextOutputTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add FlowScribeCore && git commit -m "feat(m1): SystemTextOutput (presse-papier testé + collage Cmd+V)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && git push
```

---

### Task 6: `MicrophoneRecorder` — capture AVAudioEngine → fichier CAF

**Files:**
- Modify: `FlowScribeCore/Sources/FlowScribeCore/AudioRecorder.swift`

**Interfaces:**
- Consumes: `AudioRecorder` (Task 4).
- Produces: `final class MicrophoneRecorder: AudioRecorder` (init `outputDirectory: URL`).

> Capture réelle du micro : pas de test unitaire fiable (matériel). On valide par build + run manuel. La logique testable (machine à états) est déjà couverte en Task 4.

- [ ] **Step 1: Compléter `AudioRecorder.swift`**

```swift
import Foundation
import AVFoundation

public protocol AudioRecorder: Sendable {
    func start() throws
    func stop() async -> AudioRecording
}

/// Enregistre le micro vers un fichier CAF (robuste au crash, écriture incrémentale).
public final class MicrophoneRecorder: AudioRecorder {
    private let engine = AVAudioEngine()
    private let outputDirectory: URL
    private var file: AVAudioFile?
    private var currentURL: URL?
    private var startedAt: Date?

    public init(outputDirectory: URL) {
        self.outputDirectory = outputDirectory
    }

    public func start() throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let url = outputDirectory.appending(path: "rec-\(Int(Date().timeIntervalSince1970)).caf")
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let audioFile = try AVAudioFile(forWriting: url, settings: format.settings)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak audioFile] buffer, _ in
            try? audioFile?.write(from: buffer)
        }
        engine.prepare()
        try engine.start()
        self.file = audioFile
        self.currentURL = url
        self.startedAt = Date()
    }

    public func stop() async -> AudioRecording {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let url = currentURL ?? outputDirectory.appending(path: "empty.caf")
        let duration = startedAt.map { Date().timeIntervalSince($0) }
        file = nil; currentURL = nil; startedAt = nil
        return AudioRecording(url: url, duration: duration)
    }
}
```

- [ ] **Step 2: Vérifier que le package compile**

Run: `cd FlowScribeCore && swift build`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add FlowScribeCore && git commit -m "feat(m1): MicrophoneRecorder (AVAudioEngine -> CAF)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && git push
```

---

### Task 7: `AppleSpeechEngine` — transcription fichier via SpeechAnalyzer

**Files:**
- Create: `FlowScribeCore/Sources/FlowScribeCore/AppleSpeechEngine.swift`

**Interfaces:**
- Consumes: `TranscriptionEngine` (Task 2).
- Produces: `final class AppleSpeechEngine: TranscriptionEngine` (id `"apple.local"`, `capabilities` local).

> Dépend du modèle on-device et d'un vrai fichier audio : validé par build + smoke test manuel (Task 11), pas en unit test.

- [ ] **Step 1: Écrire `AppleSpeechEngine.swift`**

```swift
import Foundation
import Speech
import AVFoundation

public enum AppleSpeechError: Error {
    case unavailable
    case localeUnsupported
    case assetDownloadInProgress
}

public final class AppleSpeechEngine: TranscriptionEngine {
    public let id = "apple.local"
    public let capabilities = EngineCapabilities(supportsStreaming: true, supportsKeyterms: false, isLocal: true)

    public init() {}

    public func transcribeFile(at url: URL, locale: Locale) async throws -> String {
        let transcriber = try await Self.makeReadyTranscriber(locale: locale)

        async let collected: AttributedString = transcriber.results.reduce(into: AttributedString()) { acc, result in
            acc += result.text
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let audioFile = try AVAudioFile(forReading: url)
        if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        let attributed = try await collected
        return String(attributed.characters)
    }

    /// Vérifie la disponibilité et installe le modèle de langue si nécessaire.
    private static func makeReadyTranscriber(locale: Locale) async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else { throw AppleSpeechError.unavailable }
        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw AppleSpeechError.localeUnsupported
        }
        let transcriber = SpeechTranscriber(locale: supported, preset: .transcription)
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            return transcriber
        default:
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
                throw AppleSpeechError.assetDownloadInProgress
            }
            return transcriber
        }
    }
}
```
> Note d'exécution : `preset`, `AssetInventory` et `analyzeSequence` correspondent à l'API documentée (macOS 26). Si une signature diffère dans le SDK installé, ajuster d'après `developer.apple.com/documentation/Speech` — la structure (vérifier dispo → installer asset → analyser → réduire les `results` en AttributedString) reste valable.

- [ ] **Step 2: Vérifier que le package compile**

Run: `cd FlowScribeCore && swift build`
Expected: Build complete.

- [ ] **Step 3: Commit**

```bash
git add FlowScribeCore && git commit -m "feat(m1): AppleSpeechEngine (transcription fichier SpeechAnalyzer)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && git push
```

---

### Task 8: Permissions — micro + reconnaissance vocale

**Files:**
- Create: `FlowScribe/Permissions.swift`

**Interfaces:**
- Produces: `enum Permissions { static func requestMicrophone() async -> Bool ; static func requestSpeech() async -> Bool }`.

> Câblage app (frameworks système) : validé par build + run manuel.

- [ ] **Step 1: Écrire `FlowScribe/Permissions.swift`**

```swift
import AVFoundation
import Speech

enum Permissions {
    static func requestMicrophone() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in cont.resume(returning: granted) }
        }
    }

    static func requestSpeech() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }
}
```

- [ ] **Step 2: Build de l'app**

Run: `xcodegen generate && xcodebuild -project FlowScribe.xcodeproj -scheme FlowScribe -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add FlowScribe && git commit -m "feat(m1): demande des permissions micro + reconnaissance vocale

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && git push
```

---

### Task 9: HUD flottant d'enregistrement (NSPanel + SwiftUI)

**Files:**
- Create: `FlowScribe/RecordingHUD.swift`

**Interfaces:**
- Consumes: `DictationState` (Task 4).
- Produces: `@MainActor final class RecordingHUD { func show(state: DictationState); func hide() }`.

> Fenêtre AppKit : validé par run manuel.

- [ ] **Step 1: Écrire `FlowScribe/RecordingHUD.swift`**

```swift
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
```

- [ ] **Step 2: Build de l'app**

Run: `xcodegen generate && xcodebuild -project FlowScribe.xcodeproj -scheme FlowScribe -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add FlowScribe && git commit -m "feat(m1): HUD flottant d'enregistrement

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && git push
```

---

### Task 10: Hotkey global + câblage `DictationController`

**Files:**
- Create: `FlowScribe/HotkeyBridge.swift`
- Modify: `FlowScribe/FlowScribeApp.swift`

**Interfaces:**
- Consumes: `DictationController` (Task 4), `PressClassifier` (Task 3), `RecordingHUD` (Task 9), `MicrophoneRecorder` (Task 6), `AppleSpeechEngine` (Task 7), `SystemTextOutput` (Task 5).
- Produces: `@MainActor final class HotkeyBridge` reliant `KeyboardShortcuts` → contrôleur + HUD.

> Câblage : validé par run manuel (Task 11).

- [ ] **Step 1: Écrire `FlowScribe/HotkeyBridge.swift`**

```swift
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
```

- [ ] **Step 2: Câbler le tout dans `FlowScribe/FlowScribeApp.swift`**

```swift
import SwiftUI
import FlowScribeCore

@main
struct FlowScribeApp: App {
    @State private var bridge: HotkeyBridge?

    var body: some Scene {
        WindowGroup("FlowScribe") {
            VStack(spacing: 12) {
                Text("FlowScribe").font(.title2.bold())
                Text("Appuie sur ⌥Espace pour dicter.").foregroundStyle(.secondary)
            }
            .frame(width: 360, height: 200)
            .task { await setup() }
        }
        MenuBarExtra("FlowScribe", systemImage: "mic.fill") {
            Button("Quitter") { NSApplication.shared.terminate(nil) }
        }
    }

    @MainActor
    private func setup() async {
        guard bridge == nil else { return }
        _ = await Permissions.requestMicrophone()
        _ = await Permissions.requestSpeech()
        let dir = URL.applicationSupportDirectory.appending(path: "FlowScribe/recordings")
        let controller = DictationController(
            recorder: MicrophoneRecorder(outputDirectory: dir),
            engine: AppleSpeechEngine(),
            output: SystemTextOutput(),
            locale: Locale(identifier: "fr-FR")
        )
        bridge = HotkeyBridge(controller: controller, hud: RecordingHUD())
    }
}
```

- [ ] **Step 3: Build de l'app**

Run: `xcodegen generate && xcodebuild -project FlowScribe.xcodeproj -scheme FlowScribe -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
git add FlowScribe && git commit -m "feat(m1): hotkey global ⌥Espace + câblage bout-en-bout

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && git push
```

---

### Task 11: Recette manuelle bout-en-bout + run

**Files:** aucun (validation).

- [ ] **Step 1: Lancer toute la suite de tests du core**

Run: `cd FlowScribeCore && swift test`
Expected: PASS (tous les tests des Tasks 1–5).

- [ ] **Step 2: Lancer l'app**

Run: `xcodebuild -project FlowScribe.xcodeproj -scheme FlowScribe -destination 'platform=macOS' build && open ~/Library/Developer/Xcode/DerivedData/FlowScribe-*/Build/Products/Debug/FlowScribe.app`
Expected: l'app se lance, icône Dock + item barre de menus présents.

- [ ] **Step 3: Accorder les permissions**

Au premier lancement : accorder Micro + Reconnaissance vocale. Puis dans Réglages Système → Confidentialité → Accessibilité, autoriser FlowScribe (nécessaire au collage Cmd+V).

- [ ] **Step 4: Test du tap (bascule)**

Ouvrir TextEdit, placer le curseur. Taper ⌥Espace (court) → HUD « Enregistrement… ». Parler en français. Re-taper ⌥Espace → HUD « Transcription… » puis le texte se colle dans TextEdit et est dans le presse-papier.
Expected: texte français cohérent collé au curseur.

- [ ] **Step 5: Test du maintien (push-to-talk)**

Maintenir ⌥Espace, parler, relâcher → le texte se colle.
Expected: collage à la fin du maintien.

- [ ] **Step 6: Commit de clôture M1**

```bash
git commit --allow-empty -m "chore(m1): recette bout-en-bout validée

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && git push
```

---

## Auto-revue (faite à l'écriture)

- **Couverture du périmètre M1** : capture (Task 6), moteur Apple local fichier (Task 7), sortie collage+presse-papier (Task 5), hotkey hybride tap/maintien (Tasks 3+4+10), HUD (Task 9), présence Dock+menu (Task 10), permissions (Task 8). ✅ Le live preview *volatil* (résultats temps réel pendant la parole), la persistance/historique, les moteurs cloud, le glossaire et le contrôle musique sont **hors M1** — couverts par les plans M2/M3/M4 (voir spec §2).
- **Placeholders** : aucun TODO/TBD ; chaque step a son code réel.
- **Cohérence des types** : `TranscriptionEngine.transcribeFile(at:locale:)`, `AudioRecorder.start()/stop()`, `TextOutput.deliver(_:)`, `PressKind`, `DictationState` sont nommés identiquement à travers les tâches consommatrices.
- **Limite assumée à signaler à l'exécution** : la capture micro, le moteur Apple et le hotkey ne sont pas couverts par des tests unitaires (matériel/OS) — validés par la recette manuelle Task 11 ; la logique pure (classifieur, machine à états, presse-papier) l'est.
```

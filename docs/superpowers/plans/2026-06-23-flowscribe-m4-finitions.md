# FlowScribe — M4 Finitions — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development ou executing-plans. (Cette session : exécution inline.)

**Goal:** Boucler la v1 : contrôle de la musique (pause/reprise pendant la dictée), nettoyage IA optionnel, polish barre de menus, et packaging en DMG notarisé.

**Architecture:** `MediaController` (machine à états pure : ne relance que ce qu'il a mis en pause) pilote un `MediaPlayer` (AppleScript Music/Spotify). `AICleanupService` envoie le transcript à un chat (Mistral/OpenAI) pour ponctuation/reformulation, testé via `Transport` mocké. Les deux sont **optionnels** (toggles, off par défaut) et branchés dans `DictationController`.

**Tech Stack:** Swift 6, FlowScribeCore (SPM), AppleScript (NSAppleScript), URLSession, SwiftUI, XCTest, create-dmg + notarytool.

## Global Constraints
- macOS 26+, Apple Silicon, Swift 6 strict.
- Musique : aucune API privée (MediaRemote exclu) ; AppleScript Music/Spotify, **ne relancer que ce qu'on a mis en pause**. Nécessite l'entitlement `com.apple.security.automation.apple-events` + `NSAppleEventsUsageDescription` (prompt Automation au 1er usage). Off par défaut.
- Nettoyage IA : off par défaut ; réutilise une clé existante ; déterministe côté requête (testable mock).
- Logique testable dans FlowScribeCore ; glue (AppleScript, packaging) dans l'app/scripts.
- Commits fréquents (français + trailer), push sur `origin m4-finitions`.

## Structure
```
FlowScribeCore/Sources/FlowScribeCore/
├── MediaController.swift     MediaSource + MediaPlayer (protocole) + MediaController (machine à états)
├── AICleanupService.swift    nettoyage via chat (Transport injectable)
FlowScribe/
├── AppleScriptMediaPlayer.swift  impl MediaPlayer (NSAppleScript Music/Spotify)
├── FlowScribe.entitlements   (+ apple-events) · Info.plist (+ NSAppleEventsUsageDescription)
└── (SettingsView/FlowScribeApp modifiés : toggles musique + nettoyage)
scripts/
└── package-dmg.sh            build release + create-dmg + notarytool + staple
```

---

### Task 1: `MediaController` (machine à états, TDD)
**Files:** Create `MediaController.swift` ; Test `MediaControllerTests.swift`.
**Interfaces:** `enum MediaSource: String, CaseIterable, Sendable { case music, spotify }` ; `protocol MediaPlayer: Sendable { func isPlaying(_:) -> Bool; func pause(_:); func play(_:) }` ; `@MainActor final class MediaController { init(player:enabled:); func pauseForDictation(); func resumeAfterDictation() }`.

- [ ] **Step 1: Test (échoue)**
```swift
import XCTest
@testable import FlowScribeCore

@MainActor
final class MediaControllerTests: XCTestCase {
    final class SpyPlayer: MediaPlayer {
        nonisolated(unsafe) var playing: Set<MediaSource>
        nonisolated(unsafe) var paused: [MediaSource] = []
        nonisolated(unsafe) var resumed: [MediaSource] = []
        init(playing: Set<MediaSource>) { self.playing = playing }
        func isPlaying(_ s: MediaSource) -> Bool { playing.contains(s) }
        func pause(_ s: MediaSource) { paused.append(s); playing.remove(s) }
        func play(_ s: MediaSource) { resumed.append(s); playing.insert(s) }
    }
    func test_pausesOnlyPlaying_resumesOnlyPaused() {
        let player = SpyPlayer(playing: [.spotify])
        let c = MediaController(player: player, enabled: true)
        c.pauseForDictation()
        XCTAssertEqual(player.paused, [.spotify])
        c.resumeAfterDictation()
        XCTAssertEqual(player.resumed, [.spotify])
    }
    func test_disabled_doesNothing() {
        let player = SpyPlayer(playing: [.music])
        let c = MediaController(player: player, enabled: false)
        c.pauseForDictation(); c.resumeAfterDictation()
        XCTAssertTrue(player.paused.isEmpty); XCTAssertTrue(player.resumed.isEmpty)
    }
    func test_nothingPlaying_resumesNothing() {
        let player = SpyPlayer(playing: [])
        let c = MediaController(player: player, enabled: true)
        c.pauseForDictation(); c.resumeAfterDictation()
        XCTAssertTrue(player.resumed.isEmpty)
    }
}
```
- [ ] **Step 2: RED**.
- [ ] **Step 3: `MediaController.swift`**
```swift
import Foundation

public enum MediaSource: String, CaseIterable, Sendable, Equatable { case music, spotify }

public protocol MediaPlayer: Sendable {
    func isPlaying(_ source: MediaSource) -> Bool
    func pause(_ source: MediaSource)
    func play(_ source: MediaSource)
}

@MainActor
public final class MediaController {
    private let player: MediaPlayer
    private let enabled: Bool
    private var paused: [MediaSource] = []
    public init(player: MediaPlayer, enabled: Bool) { self.player = player; self.enabled = enabled }

    /// Met en pause ce qui joue ; mémorise pour ne relancer que ça.
    public func pauseForDictation() {
        guard enabled else { return }
        paused = []
        for s in MediaSource.allCases where player.isPlaying(s) { player.pause(s); paused.append(s) }
    }
    /// Relance exactement ce qu'on a mis en pause.
    public func resumeAfterDictation() {
        for s in paused { player.play(s) }
        paused = []
    }
}
```
- [ ] **Step 4: GREEN**.
- [ ] **Step 5: Commit** `feat(m4): MediaController (machine à états, ne relance que ce qu'il a pausé)`.

---

### Task 2: `AppleScriptMediaPlayer` + branchement
**Files:** Create `FlowScribe/AppleScriptMediaPlayer.swift` ; Modify `FlowScribe.entitlements` (+ apple-events), `project.yml` Info (+ NSAppleEventsUsageDescription), `FlowScribeApp.swift` (créer MediaController, le passer au DictationController), `DictationController.swift` (pause au start, reprise à la fin).
> Glue AppleScript : build + recette manuelle.

- [ ] **Step 1: `AppleScriptMediaPlayer.swift`** — `isPlaying`/`pause`/`play` via `NSAppleScript` :
```swift
import Foundation
import FlowScribeCore

struct AppleScriptMediaPlayer: MediaPlayer {
    private func appName(_ s: MediaSource) -> String { s == .music ? "Music" : "Spotify" }
    private func run(_ script: String) -> String? {
        var error: NSDictionary?
        let out = NSAppleScript(source: script)?.executeAndReturnError(&error)
        return out?.stringValue
    }
    func isPlaying(_ s: MediaSource) -> Bool {
        let app = appName(s)
        let script = "if application \"\(app)\" is running then tell application \"\(app)\" to return (player state as text)\nreturn \"stopped\""
        return run(script)?.contains("playing") ?? false
    }
    func pause(_ s: MediaSource) { _ = run("tell application \"\(appName(s))\" to pause") }
    func play(_ s: MediaSource) { _ = run("tell application \"\(appName(s))\" to play") }
}
```
- [ ] **Step 2: Entitlement + usage description** — ajouter `com.apple.security.automation.apple-events` à `FlowScribe.entitlements` ; `NSAppleEventsUsageDescription` à l'Info (project.yml) : "FlowScribe met votre musique en pause pendant la dictée."
- [ ] **Step 3: `DictationController`** — accepter un `mediaController` optionnel ; `pauseForDictation()` au début de l'enregistrement (dans `pressDown` quand on passe à `.recording`) et `resumeAfterDictation()` à la fin de `finishRecording`. Adapter le test si signature change (injection optionnelle, défaut nil → comportement inchangé).
- [ ] **Step 4: `FlowScribeApp`** — construire `MediaController(player: AppleScriptMediaPlayer(), enabled: settings.musicControlEnabled)` et l'injecter ; reconstruire via `onChange`.
- [ ] **Step 5: Build** `xcodegen generate && xcodebuild ... build` → SUCCEEDED. **Commit** `feat(m4): contrôle musique (AppleScript Music/Spotify) branché`.

---

### Task 3: `AICleanupService` (nettoyage IA, TDD)
**Files:** Create `AICleanupService.swift` ; Test `AICleanupServiceTests.swift`.
**Interfaces:** `struct CleanupConfig: Sendable { endpoint, model, authHeaderName, authValuePrefix }` (statics `.mistral`, `.openAI`) ; `struct AICleanupService { init(config:apiKey:transport:); func cleanup(_ text: String) async throws -> String }`. POST chat completions, system prompt = corriger ponctuation + retirer hésitations sans changer le sens, parse `choices[0].message.content`.

- [ ] **Step 1: Test (échoue)**
```swift
import XCTest
@testable import FlowScribeCore

final class AICleanupServiceTests: XCTestCase {
    func test_cleanup_postsChat_andParsesContent() async throws {
        let body = #"{"choices":[{"message":{"content":"Bonjour, ceci est propre."}}]}"#
        let mock = MockTransport(statusCode: 200, body: Data(body.utf8))
        let svc = AICleanupService(config: .mistral, apiKey: "k", transport: mock)
        let out = try await svc.cleanup("euh bonjour ceci est euh propre")
        XCTAssertEqual(out, "Bonjour, ceci est propre.")
        let req = mock.lastRequest
        XCTAssertEqual(req?.httpMethod, "POST")
        XCTAssertEqual(req?.url, CleanupConfig.mistral.endpoint)
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Authorization"), "Bearer k")
    }
    func test_cleanup_throwsOnHTTPError() async {
        let svc = AICleanupService(config: .openAI, apiKey: "bad", transport: MockTransport(statusCode: 401))
        do { _ = try await svc.cleanup("x"); XCTFail() } catch {}
    }
}
```
- [ ] **Step 2: RED**.
- [ ] **Step 3: `AICleanupService.swift`** — code complet :
```swift
import Foundation

public struct CleanupConfig: Sendable {
    public let endpoint: URL
    public let model: String
    public let authHeaderName: String
    public let authValuePrefix: String
    public static let mistral = CleanupConfig(endpoint: URL(string: "https://api.mistral.ai/v1/chat/completions")!,
        model: "mistral-small-latest", authHeaderName: "Authorization", authValuePrefix: "Bearer ")
    public static let openAI = CleanupConfig(endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!,
        model: "gpt-4o-mini", authHeaderName: "Authorization", authValuePrefix: "Bearer ")
}

public enum AICleanupError: Error { case httpError(Int), badResponse }

public struct AICleanupService: Sendable {
    private let config: CleanupConfig
    private let apiKey: String
    private let transport: Transport
    public init(config: CleanupConfig, apiKey: String, transport: Transport) {
        self.config = config; self.apiKey = apiKey; self.transport = transport
    }
    public func cleanup(_ text: String) async throws -> String {
        let system = "Corrige la ponctuation et la casse, retire les hésitations (euh, hum) et répétitions, SANS changer le sens ni la langue. Réponds UNIQUEMENT le texte corrigé."
        let payload: [String: Any] = [
            "model": config.model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": text]],
            "temperature": 0.2
        ]
        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("\(config.authValuePrefix)\(apiKey)", forHTTPHeaderField: config.authHeaderName)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw AICleanupError.httpError(response.statusCode) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else { throw AICleanupError.badResponse }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```
- [ ] **Step 4: GREEN**. **Commit** `feat(m4): AICleanupService (nettoyage via chat, testé mock)`.

---

### Task 4: Brancher le nettoyage IA (toggle)
**Files:** Modify `SettingsStore` (+ `cleanupEnabled`, `cleanupProvider`), `SettingsView` (toggle + choix), `FlowScribeApp`/`DictationController` (appliquer après la post-correction si activé).
- [ ] **Step 1**: `SettingsStore` : `var cleanupEnabled: Bool` (UserDefaults, défaut false) + didSet onChange. 
- [ ] **Step 2**: appliquer dans le flux de dictée : après `output.deliver`, si activé, lancer le nettoyage et re-livrer le texte nettoyé (ou avant collage). Décision d'implémentation : nettoyer **avant** collage si activé (collage = texte propre). Le contrôleur appelle un `cleanup: (String) async -> String` injecté (nil = pas de nettoyage). 
- [ ] **Step 3**: Build + Commit `feat(m4): toggle nettoyage IA branché`.

---

### Task 5: Polish barre de menus + réglages
**Files:** Modify `FlowScribeApp` (MenuBarExtra : statut + ouvrir Réglages), `SettingsView` (toggles musique + nettoyage dans une section).
- [ ] Build + Commit `feat(m4): polish barre de menus + toggles réglages`.

---

### Task 6: DMG notarisé (PORTE HUMAINE)
**Files:** Create `scripts/package-dmg.sh`.
- [ ] **Step 1**: script : `xcodebuild -scheme FlowScribe -configuration Release build`, localiser le `.app`, `create-dmg` (ou hdiutil), `xcrun notarytool submit --wait` (credentials Apple de l'utilisateur), `xcrun stapler staple`.
- [ ] **Step 2 (PORTE HUMAINE)**: l'utilisateur fournit ses identifiants notarytool (Apple ID + mot de passe app-specific, ou keychain profile) ; lance le script ; vérifie le DMG notarisé.
- [ ] **Step 3**: Commit `chore(m4): script de packaging DMG notarisé`.

---

## Auto-revue (à l'écriture)
- Couverture M4 : musique (T1 logique testée + T2 glue), nettoyage IA (T3 testé + T4 branché), polish (T5), packaging notarisé (T6 porte humaine). ✅
- Placeholders : T1 et T3 code complet + tests ; T2/T4/T5/T6 étapes concrètes (glue/UI/scripts validés par build + manuel).
- Cohérence : `MediaController.pauseForDictation()/resumeAfterDictation()`, `MediaPlayer.isPlaying/pause/play`, `AICleanupService.cleanup(_:)`, `CleanupConfig.mistral/.openAI`.

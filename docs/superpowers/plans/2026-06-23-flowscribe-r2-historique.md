# R2 — Persistance & historique — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development ou executing-plans. (Cette session : exécution inline.)

**Goal:** Stocker les transcriptions et les exploiter depuis l'Accueil (liste, recherche, copier, re-transcrire, supprimer) avec rétention configurable.

**Architecture:** `TranscriptionRecord` (Codable) + `HistoryStore` (JSON) côté core ; `RetentionPolicy` pure ; le `DictationController` émet un record en fin de dictée via `onRecord` ; un `HistoryModel` (@Observable, app) republie la liste pour l'UI ; `HomeView` liste + actions.

**Tech Stack:** Swift 6, FlowScribeCore (SPM, JSON Codable), SwiftUI, XCTest.

## Global Constraints
- macOS 26+, Apple Silicon, Swift 6.
- Persistance JSON (`history.json` dans Application Support/FlowScribe) ; in-memory pour tests.
- `RetentionPolicy` + `HistoryStore` (in-memory) + hook `onRecord` = **TDD**. UI = build + recette.
- Audio dans `Application Support/FlowScribe/recordings` ; le record stocke le **nom** de fichier.
- Record créé uniquement sur **dictée réussie**. Rétention défaut **30 j** (0 = illimité).
- Commits fréquents (français + trailer), push sur `origin r2-historique`.

## Structure
```
FlowScribeCore/Sources/FlowScribeCore/
├── TranscriptionRecord.swift   modèle Codable
├── RetentionPolicy.swift       pur (expired)
├── HistoryStore.swift          protocole + InMemory + JSON
├── DictationController.swift   (modifié) onRecord
FlowScribe/
├── HistoryModel.swift          @Observable (app) : republie records, add/delete/purge/retranscribe helpers
├── HomeView.swift              (modifié) liste + recherche + actions
├── SettingsView.swift          (modifié) section Rétention
└── FlowScribeApp.swift         (modifié) stores + câblage onRecord + purge au lancement + re-transcription
```

---

### Task 1: `TranscriptionRecord` + `RetentionPolicy` (cœur, TDD)
**Files:** Create `TranscriptionRecord.swift`, `RetentionPolicy.swift` ; Test `RetentionPolicyTests.swift`.
**Interfaces:** `struct TranscriptionRecord: Codable, Identifiable, Equatable, Sendable { id, date, text, engineId, locale, audioFileName, duration }` ; `enum RetentionPolicy { static func expired(_:now:maxAgeDays:) -> [TranscriptionRecord] }`.

- [ ] **Step 1: Test (échoue)**
```swift
import XCTest
@testable import FlowScribeCore

final class RetentionPolicyTests: XCTestCase {
    private func rec(_ ageDays: Double) -> TranscriptionRecord {
        TranscriptionRecord(id: UUID(), date: Date(timeIntervalSinceNow: -ageDays * 86_400),
                            text: "t", engineId: "e", locale: "fr-FR", audioFileName: "a.caf", duration: 1)
    }
    func test_maxAgeZero_neverExpires() {
        XCTAssertTrue(RetentionPolicy.expired([rec(100)], now: Date(), maxAgeDays: 0).isEmpty)
    }
    func test_expiresBeyondMaxAge() {
        let old = rec(40), young = rec(5)
        let expired = RetentionPolicy.expired([old, young], now: Date(), maxAgeDays: 30)
        XCTAssertEqual(expired.map(\.id), [old.id])
    }
}
```
- [ ] **Step 2: RED** — `cd FlowScribeCore && swift test --filter RetentionPolicyTests`.
- [ ] **Step 3: `TranscriptionRecord.swift`**
```swift
import Foundation

public struct TranscriptionRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let text: String
    public let engineId: String
    public let locale: String
    public let audioFileName: String
    public let duration: TimeInterval?
    public init(id: UUID, date: Date, text: String, engineId: String, locale: String, audioFileName: String, duration: TimeInterval?) {
        self.id = id; self.date = date; self.text = text; self.engineId = engineId
        self.locale = locale; self.audioFileName = audioFileName; self.duration = duration
    }
}
```
- [ ] **Step 4: `RetentionPolicy.swift`**
```swift
import Foundation

public enum RetentionPolicy {
    /// Records expirés (plus vieux que maxAgeDays). maxAgeDays <= 0 ⇒ aucun n'expire.
    public static func expired(_ records: [TranscriptionRecord], now: Date, maxAgeDays: Int) -> [TranscriptionRecord] {
        guard maxAgeDays > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-Double(maxAgeDays) * 86_400)
        return records.filter { $0.date < cutoff }
    }
}
```
- [ ] **Step 5: GREEN** ; **Commit** `feat(r2): TranscriptionRecord + RetentionPolicy (pur, testé)`.

---

### Task 2: `HistoryStore` (cœur, TDD)
**Files:** Create `HistoryStore.swift` ; Test `HistoryStoreTests.swift`.
**Interfaces:** `protocol HistoryStore: Sendable { var records: [TranscriptionRecord] { get } ; func add(_:) ; func delete(id: UUID) }` (records **plus récent d'abord**) ; `InMemoryHistoryStore` ; `JSONHistoryStore(url:)`.

- [ ] **Step 1: Test (échoue)**
```swift
import XCTest
@testable import FlowScribeCore

final class HistoryStoreTests: XCTestCase {
    private func rec(_ id: UUID, _ ageSec: Double) -> TranscriptionRecord {
        TranscriptionRecord(id: id, date: Date(timeIntervalSinceNow: -ageSec), text: "t",
                            engineId: "e", locale: "fr-FR", audioFileName: "\(id).caf", duration: 1)
    }
    func test_add_sortsNewestFirst_andDelete() {
        let store = InMemoryHistoryStore()
        let older = UUID(), newer = UUID()
        store.add(rec(older, 100)); store.add(rec(newer, 1))
        XCTAssertEqual(store.records.map(\.id), [newer, older])
        store.delete(id: older)
        XCTAssertEqual(store.records.map(\.id), [newer])
    }
}
```
- [ ] **Step 2: RED**.
- [ ] **Step 3: `HistoryStore.swift`**
```swift
import Foundation

public protocol HistoryStore: Sendable {
    var records: [TranscriptionRecord] { get }   // plus récent d'abord
    func add(_ record: TranscriptionRecord)
    func delete(id: UUID)
}

public final class InMemoryHistoryStore: HistoryStore, @unchecked Sendable {
    private var storage: [TranscriptionRecord] = []
    private let lock = NSLock()
    public init() {}
    public var records: [TranscriptionRecord] {
        lock.lock(); defer { lock.unlock() }; return storage.sorted { $0.date > $1.date }
    }
    public func add(_ record: TranscriptionRecord) {
        lock.lock(); defer { lock.unlock() }; storage.append(record)
    }
    public func delete(id: UUID) {
        lock.lock(); defer { lock.unlock() }; storage.removeAll { $0.id == id }
    }
}

public final class JSONHistoryStore: HistoryStore, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var storage: [TranscriptionRecord]
    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([TranscriptionRecord].self, from: data) {
            storage = decoded
        } else { storage = [] }
    }
    public var records: [TranscriptionRecord] {
        lock.lock(); defer { lock.unlock() }; return storage.sorted { $0.date > $1.date }
    }
    public func add(_ record: TranscriptionRecord) {
        lock.lock(); storage.append(record); lock.unlock(); persist()
    }
    public func delete(id: UUID) {
        lock.lock(); storage.removeAll { $0.id == id }; lock.unlock(); persist()
    }
    private func persist() {
        lock.lock(); let snap = storage; lock.unlock()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(snap) { try? data.write(to: url) }
    }
}
```
> Note : pour décoder, `JSONDecoder` doit utiliser `.iso8601` aussi. Ajuster : créer le decoder dans `init` avec `dateDecodingStrategy = .iso8601`.
- [ ] **Step 4:** corriger le décodage dans `init` :
```swift
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: url), let decoded = try? dec.decode([TranscriptionRecord].self, from: data) {
            storage = decoded
        } else { storage = [] }
```
- [ ] **Step 5: GREEN** ; **Commit** `feat(r2): HistoryStore (JSON + in-memory, tri récent d'abord)`.

---

### Task 3: `DictationController.onRecord`
**Files:** Modify `DictationController.swift` ; Test `DictationControllerTests.swift` (ajout).
**Interfaces:** `DictationController.onRecord: ((TranscriptionRecord) -> Void)?` — appelé en fin de dictée réussie avec le texte final + `engineId` + audio.

- [ ] **Step 1: Test (échoue)** — ajouter
```swift
    func test_onRecord_receivesFinalTextAndEngine() async {
        let (c, _, _) = makeController()   // primaire "mock" -> "salut"
        var rec: TranscriptionRecord?
        c.onRecord = { rec = $0 }
        c.pressDown(); await c.pressUp(kind: .hold)
        XCTAssertEqual(rec?.text, "salut")
        XCTAssertEqual(rec?.engineId, "mock")
        XCTAssertEqual(rec?.audioFileName, "a.caf")
    }
```
- [ ] **Step 2: RED**.
- [ ] **Step 3: Modifier `finishRecording()`** dans `DictationController.swift` — ajouter la propriété `public var onRecord: ((TranscriptionRecord) -> Void)?` et, dans le `case .success`, capturer `engineId` et émettre le record :
```swift
    public var onRecord: ((TranscriptionRecord) -> Void)?

    private func finishRecording() async {
        guard state == .recording else { return }
        let recording = await recorder.stop()
        state = .transcribing
        let outcome = await service.transcribe(fileAt: recording.url, locale: locale)
        switch outcome {
        case let .success(text, engineId, _):
            var finalText = text
            if let cleanup { finalText = await cleanup(finalText) }
            lastTranscript = finalText
            output.deliver(finalText)
            onRecord?(TranscriptionRecord(
                id: UUID(), date: Date(), text: finalText, engineId: engineId,
                locale: locale.identifier, audioFileName: recording.url.lastPathComponent,
                duration: recording.duration))
        case .failed:
            lastTranscript = nil
        }
        state = .idle
        mediaController?.resumeAfterDictation()
        onFinish?(outcome)
    }
```
- [ ] **Step 4: GREEN** (`swift test`) ; **Commit** `feat(r2): DictationController émet un TranscriptionRecord (onRecord)`.

---

### Task 4: Intégration app — store, câblage, purge, rétention
**Files:** Create `FlowScribe/HistoryModel.swift` ; Modify `FlowScribe/FlowScribeApp.swift`, `FlowScribe/SettingsStore.swift`, `FlowScribe/SettingsView.swift`.
> Build + recette.

- [ ] **Step 1: `HistoryModel.swift`** (app, @Observable)
```swift
import SwiftUI
import FlowScribeCore

@MainActor
@Observable
final class HistoryModel {
    private let store: HistoryStore
    private let recordingsDir: URL
    var records: [TranscriptionRecord] = []

    init(store: HistoryStore, recordingsDir: URL) {
        self.store = store; self.recordingsDir = recordingsDir
        records = store.records
    }
    func add(_ r: TranscriptionRecord) { store.add(r); records = store.records }
    func delete(_ r: TranscriptionRecord) { store.delete(id: r.id); deleteAudio(r.audioFileName); records = store.records }
    func purge(maxAgeDays: Int) {
        for r in RetentionPolicy.expired(store.records, now: Date(), maxAgeDays: maxAgeDays) {
            store.delete(id: r.id); deleteAudio(r.audioFileName)
        }
        records = store.records
    }
    func audioURL(_ name: String) -> URL { recordingsDir.appending(path: name) }
    func audioExists(_ name: String) -> Bool { FileManager.default.fileExists(atPath: audioURL(name).path) }
    private func deleteAudio(_ name: String) { try? FileManager.default.removeItem(at: audioURL(name)) }
}
```
- [ ] **Step 2: `SettingsStore`** — ajouter `var retentionDays: Int` (UserDefaults `retentionDays`, défaut 30) avec didSet de persistance (pas besoin d'`onChange` pipeline). Dans `init` : `self.retentionDays = defaults.object(forKey: "retentionDays") as? Int ?? 30`.
- [ ] **Step 3: `SettingsView`** — section « Rétention » : `Stepper("Conserver \(settings.retentionDays) jours (0 = illimité)", value: $settings.retentionDays, in: 0...365)`.
- [ ] **Step 4: `FlowScribeApp`** — créer le store + model, câbler `onRecord`, purger au lancement, fournir la re-transcription :
```swift
    @State private var history = HistoryModel(
        store: JSONHistoryStore(url: URL.applicationSupportDirectory.appending(path: "FlowScribe/history.json")),
        recordingsDir: URL.applicationSupportDirectory.appending(path: "FlowScribe/recordings"))
```
Dans `setup()`, après création de `c` : `c.onRecord = { [history] r in history.add(r) }` et `history.purge(maxAgeDays: settings.retentionDays)`. Passer `history` + `onRetranscribe` à `RootView`/`HomeView`. Ajouter :
```swift
    @MainActor
    private func retranscribe(_ r: TranscriptionRecord, with provider: EngineProvider) async {
        let url = history.audioURL(r.audioFileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let apple = AppleSpeechEngine()
        let primary = provider.makeEngine(apiKey: settings.apiKey(for: provider), transport: URLSessionTransport()) ?? apple
        let service = TranscriptionService(primary: primary, fallback: apple, postCorrector: PostCorrector(store: profiles))
        let outcome = await service.transcribe(fileAt: url, locale: Locale(identifier: r.locale))
        if case let .success(text, engineId, _) = outcome {
            history.add(TranscriptionRecord(id: UUID(), date: Date(), text: text, engineId: engineId,
                                            locale: r.locale, audioFileName: r.audioFileName, duration: r.duration))
        }
    }
```
`RootView` reçoit `history` et `onRetranscribe: (TranscriptionRecord, EngineProvider) async -> Void`, les passe à `HomeView`.
- [ ] **Step 5: Build** → SUCCEEDED ; **Commit** `feat(r2): intégration historique (store, onRecord, purge, rétention)`.

---

### Task 5: Accueil — liste, recherche, actions (PORTE HUMAINE)
**Files:** Modify `FlowScribe/HomeView.swift` (et `RootView.swift` pour passer `history`/`onRetranscribe`).
> Build + recette.

- [ ] **Step 1: `HomeView`** — ajouter la liste réelle. Signature : `HomeView(settings:permissions:history:onToggleRecord:onRetranscribe:)`. Corps :
```swift
import SwiftUI
import FlowScribeCore

struct HomeView: View {
    let settings: SettingsStore
    let permissions: PermissionsModel
    let history: HistoryModel
    let onToggleRecord: () -> Void
    let onRetranscribe: (TranscriptionRecord, EngineProvider) async -> Void
    @State private var query = ""

    private var filtered: [TranscriptionRecord] {
        query.isEmpty ? history.records
            : history.records.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 12) {
            if !permissions.allGranted { PermissionsView(model: permissions); Divider() }
            HStack {
                Button(action: onToggleRecord) {
                    Image(systemName: "mic.fill").font(.system(size: 18)).frame(width: 44, height: 44)
                }
                .buttonStyle(.glassProminent).clipShape(Circle())
                Text("Moteur : \(settings.defaultProvider.displayName)").foregroundStyle(.secondary)
                Spacer()
            }
            TextField("Rechercher…", text: $query).textFieldStyle(.roundedBorder)
            if filtered.isEmpty {
                Spacer(); Text("Aucune transcription.").foregroundStyle(.secondary); Spacer()
            } else {
                List(filtered) { r in row(r) }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ r: TranscriptionRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(r.text).lineLimit(3)
            HStack(spacing: 8) {
                Text(r.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                Text("· \(r.engineId)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copier") { copy(r.text) }.buttonStyle(.borderless)
                Menu("Re-transcrire") {
                    ForEach(EngineProvider.allCases, id: \.self) { p in
                        Button(p.displayName) { Task { await onRetranscribe(r, p) } }
                    }
                }.disabled(!history.audioExists(r.audioFileName))
                Button(role: .destructive) { history.delete(r) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
```
- [ ] **Step 2: `RootView`** — passer `history` + `onRetranscribe` à `HomeView` (ajouter ces paramètres à `RootView` et les transmettre).
- [ ] **Step 3: Build** → SUCCEEDED.
- [ ] **Step 4: Recette (PORTE HUMAINE)** : dicter → la transcription apparaît dans la liste Accueil ; rechercher ; copier ; re-transcrire (choisir un moteur) → nouvelle entrée ; supprimer ; relancer → l'historique persiste ; régler la rétention.
- [ ] **Step 5: Commit** `feat(r2): Accueil liste l'historique (recherche, copier, re-transcrire, supprimer)`.

---

## Auto-revue (à l'écriture)
- **Couverture spec** : record (T1) · rétention pure (T1) · HistoryStore (T2) · onRecord (T3) · store+purge+rétention+câblage+re-transcription (T4) · Accueil liste/recherche/copier/re-transcrire/supprimer (T5). ✅
- **Hors R2** : switch modèle Accueil (R3), Fichiers (R4), refonte règles (R5), motion (R6).
- **Placeholders** : aucun ; T1-T3 code+tests complets ; T4-T5 code complet (UI). `JSONDecoder`/`Encoder` en `.iso8601` (cohérent encode/decode).
- **Cohérence types** : `TranscriptionRecord(id:date:text:engineId:locale:audioFileName:duration:)`, `RetentionPolicy.expired(_:now:maxAgeDays:)`, `HistoryStore.records/add/delete(id:)`, `DictationController.onRecord`, `HistoryModel.add/delete/purge/audioURL/audioExists`, `HomeView(... history: onRetranscribe:)` cohérents.

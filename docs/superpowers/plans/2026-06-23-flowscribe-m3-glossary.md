# FlowScribe — M3 Glossaire auto-calibrant — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development ou executing-plans. (Cette session : exécution inline, dispatch de sous-agents en panne.)

**Goal:** « Zéro correction » — corriger automatiquement les erreurs de jargon par moteur, via un glossaire + une post-correction déterministe alimentée par une **calibration par lecture** (l'utilisateur lit un texte de référence, on aligne la transcription, on propose des règles `entendu → correct` propres au moteur).

**Architecture:** Brique pure `Aligner` (alignement de tokens Needleman-Wunsch) → `CalibrationService` propose des `CorrectionRule` en comparant lecture vs référence, en ciblant les termes du `GlossaryStore`. Les règles vivent dans un `CorrectionProfileStore` **par moteur** (JSON). `PostCorrector` les applique après transcription, branché dans `TranscriptionService`. Démontré : Apple entend « Doi », ElevenLabs « Doc Ploy » pour « Dokploy » → correction par moteur indispensable.

**Tech Stack:** Swift 6, FlowScribeCore (SPM), JSON (Codable) pour la persistance, SwiftUI (éditeur glossaire + calibration), XCTest.

## Global Constraints

- macOS 26+, Apple Silicon, Swift 6 strict.
- Post-correction **déterministe** (pas d'IA en M3 ; la passe IA de proposition est différée M3b).
- Règles **par moteur** (`engineId`) : Apple et ElevenLabs ne se trompent pas pareil.
- Humain dans la boucle : les règles proposées par calibration sont **validées** par l'utilisateur avant d'être enregistrées.
- Persistance JSON dans Application Support ; variante in-memory pour les tests. Aucune dépendance réseau dans le cœur.
- `Aligner` et `PostCorrector` sont des **fonctions pures** → couverture TDD prioritaire.
- Commits fréquents (français + trailer), push sur `origin m3-glossary` après chaque tâche.
- Différé en M3b (hors M3) : keyterms natifs par fournisseur (API à confirmer), passe IA de proposition, import de document → extraction de termes.

## Structure de fichiers

```
FlowScribeCore/Sources/FlowScribeCore/
├── Aligner.swift                tokenisation + alignement NW (pur)
├── CorrectionRule.swift         struct CorrectionRule (heard, replacement)
├── CorrectionProfileStore.swift protocole + InMemory + JSONFile (par moteur)
├── PostCorrector.swift          applique les règles d'un moteur à un texte (pur sur l'entrée)
├── GlossaryStore.swift          protocole + InMemory + JSONFile (termes)
├── CalibrationService.swift     propose des CorrectionRule (référence vs hypothèse, ciblé glossaire)
└── TranscriptionService.swift   (modifié) applique la post-correction après transcription
FlowScribeCore/Tests/FlowScribeCoreTests/
├── AlignerTests.swift
├── PostCorrectorTests.swift
├── CalibrationServiceTests.swift
├── GlossaryStoreTests.swift
└── TranscriptionServiceTests.swift (étendu)
FlowScribe/
├── GlossaryView.swift           éditeur de termes + règles par moteur
├── CalibrationView.swift        lit un texte → enregistre → transcrit → propose → valide
└── (SettingsView modifié : onglets/sections Glossaire + Calibration)
```

---

### Task 1: `Aligner` — tokenisation + alignement (pur)

**Files:** Create `Aligner.swift` ; Test `AlignerTests.swift`

**Interfaces:**
- Produces: `struct AlignedPair: Equatable, Sendable { let reference: String?; let hypothesis: String? }` ; `enum Aligner { static func tokenize(_:) -> [String] ; static func align(reference: [String], hypothesis: [String]) -> [AlignedPair] }`.

- [ ] **Step 1: Test (échoue)**

```swift
import XCTest
@testable import FlowScribeCore

final class AlignerTests: XCTestCase {
    func test_tokenize_lowercasesAndStripsPunctuation() {
        XCTAssertEqual(Aligner.tokenize("Bonjour, Dokploy!"), ["bonjour", "dokploy"])
    }
    func test_align_substitution() {
        // "dokploy" entendu "doi"
        let pairs = Aligner.align(reference: ["dokploy"], hypothesis: ["doi"])
        XCTAssertEqual(pairs, [AlignedPair(reference: "dokploy", hypothesis: "doi")])
    }
    func test_align_identical() {
        let pairs = Aligner.align(reference: ["a", "b"], hypothesis: ["a", "b"])
        XCTAssertEqual(pairs, [AlignedPair(reference: "a", hypothesis: "a"),
                               AlignedPair(reference: "b", hypothesis: "b")])
    }
    func test_align_insertion_splitWord() {
        // "dokploy" entendu "doc" "ploy"
        let pairs = Aligner.align(reference: ["dokploy"], hypothesis: ["doc", "ploy"])
        // une substitution + une insertion (ref nil)
        XCTAssertTrue(pairs.contains(AlignedPair(reference: "dokploy", hypothesis: "doc")))
        XCTAssertTrue(pairs.contains(AlignedPair(reference: nil, hypothesis: "ploy")))
    }
}
```

- [ ] **Step 2: Lancer — RED** — `cd FlowScribeCore && swift test --filter AlignerTests` → FAIL.

- [ ] **Step 3: `Aligner.swift`**

```swift
import Foundation

public struct AlignedPair: Equatable, Sendable {
    public let reference: String?
    public let hypothesis: String?
    public init(reference: String?, hypothesis: String?) {
        self.reference = reference; self.hypothesis = hypothesis
    }
}

public enum Aligner {
    public static func tokenize(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    /// Alignement de tokens (Needleman-Wunsch, coût 1 pour sub/insert/delete).
    public static func align(reference: [String], hypothesis: [String]) -> [AlignedPair] {
        let n = reference.count, m = hypothesis.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in 0...n { dp[i][0] = i }
        for j in 0...m { dp[0][j] = j }
        if n > 0 && m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let cost = reference[i-1] == hypothesis[j-1] ? 0 : 1
                    dp[i][j] = min(dp[i-1][j-1] + cost, dp[i-1][j] + 1, dp[i][j-1] + 1)
                }
            }
        }
        var pairs: [AlignedPair] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0 && j > 0 {
                let cost = reference[i-1] == hypothesis[j-1] ? 0 : 1
                if dp[i][j] == dp[i-1][j-1] + cost {
                    pairs.append(AlignedPair(reference: reference[i-1], hypothesis: hypothesis[j-1]))
                    i -= 1; j -= 1; continue
                }
            }
            if i > 0 && dp[i][j] == dp[i-1][j] + 1 {
                pairs.append(AlignedPair(reference: reference[i-1], hypothesis: nil))
                i -= 1; continue
            }
            pairs.append(AlignedPair(reference: nil, hypothesis: hypothesis[j-1]))
            j -= 1
        }
        return pairs.reversed()
    }
}
```

- [ ] **Step 4: Lancer — GREEN** — `swift test --filter AlignerTests`.
- [ ] **Step 5: Commit** — `feat(m3): Aligner (tokenisation + alignement NW, pur)`.

---

### Task 2: `CorrectionRule` + `CorrectionProfileStore`

**Files:** Create `CorrectionRule.swift`, `CorrectionProfileStore.swift` ; Test dans `PostCorrectorTests.swift` (in-memory).

**Interfaces:**
- Produces: `struct CorrectionRule: Codable, Equatable, Sendable { let heard: String; let replacement: String }` ; `protocol CorrectionProfileStore: Sendable { func rules(for engineId: String) -> [CorrectionRule]; func setRules(_:for:); func add(_ rule: CorrectionRule, for engineId: String) }` ; `final class InMemoryCorrectionProfileStore` ; `final class JSONCorrectionProfileStore` (init `url:`).

- [ ] **Step 1: Test (échoue)** dans `PostCorrectorTests.swift`

```swift
import XCTest
@testable import FlowScribeCore

final class PostCorrectorTests: XCTestCase {
    func test_profileStore_perEngine_roundTrip() {
        let store = InMemoryCorrectionProfileStore()
        store.add(CorrectionRule(heard: "doi", replacement: "Dokploy"), for: "apple.local")
        store.add(CorrectionRule(heard: "doc ploy", replacement: "Dokploy"), for: "elevenlabs.scribe")
        XCTAssertEqual(store.rules(for: "apple.local"), [CorrectionRule(heard: "doi", replacement: "Dokploy")])
        XCTAssertEqual(store.rules(for: "elevenlabs.scribe").first?.replacement, "Dokploy")
        XCTAssertTrue(store.rules(for: "openai.gpt-4o-transcribe").isEmpty)
    }
}
```

- [ ] **Step 2: RED** — `swift test --filter PostCorrectorTests`.

- [ ] **Step 3: `CorrectionRule.swift`**

```swift
import Foundation

public struct CorrectionRule: Codable, Equatable, Sendable {
    public let heard: String
    public let replacement: String
    public init(heard: String, replacement: String) {
        self.heard = heard; self.replacement = replacement
    }
}
```

- [ ] **Step 4: `CorrectionProfileStore.swift`**

```swift
import Foundation

public protocol CorrectionProfileStore: Sendable {
    func rules(for engineId: String) -> [CorrectionRule]
    func setRules(_ rules: [CorrectionRule], for engineId: String)
    func add(_ rule: CorrectionRule, for engineId: String)
}

public final class InMemoryCorrectionProfileStore: CorrectionProfileStore, @unchecked Sendable {
    private var byEngine: [String: [CorrectionRule]] = [:]
    private let lock = NSLock()
    public init() {}
    public func rules(for engineId: String) -> [CorrectionRule] {
        lock.lock(); defer { lock.unlock() }; return byEngine[engineId] ?? []
    }
    public func setRules(_ rules: [CorrectionRule], for engineId: String) {
        lock.lock(); defer { lock.unlock() }; byEngine[engineId] = rules
    }
    public func add(_ rule: CorrectionRule, for engineId: String) {
        lock.lock(); defer { lock.unlock() }
        var arr = byEngine[engineId] ?? []
        if !arr.contains(rule) { arr.append(rule) }
        byEngine[engineId] = arr
    }
}

/// Persistance JSON (Application Support). Charge en mémoire, réécrit à chaque modif.
public final class JSONCorrectionProfileStore: CorrectionProfileStore, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var byEngine: [String: [CorrectionRule]]

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: [CorrectionRule]].self, from: data) {
            byEngine = decoded
        } else {
            byEngine = [:]
        }
    }
    public func rules(for engineId: String) -> [CorrectionRule] {
        lock.lock(); defer { lock.unlock() }; return byEngine[engineId] ?? []
    }
    public func setRules(_ rules: [CorrectionRule], for engineId: String) {
        lock.lock(); byEngine[engineId] = rules; lock.unlock(); persist()
    }
    public func add(_ rule: CorrectionRule, for engineId: String) {
        lock.lock()
        var arr = byEngine[engineId] ?? []
        if !arr.contains(rule) { arr.append(rule) }
        byEngine[engineId] = arr
        lock.unlock(); persist()
    }
    private func persist() {
        lock.lock(); let snapshot = byEngine; lock.unlock()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url) }
    }
}
```

- [ ] **Step 5: GREEN** — `swift test --filter PostCorrectorTests`.
- [ ] **Step 6: Commit** — `feat(m3): CorrectionRule + CorrectionProfileStore (par moteur, JSON)`.

---

### Task 3: `PostCorrector` (application déterministe)

**Files:** Create `PostCorrector.swift` ; Test étend `PostCorrectorTests.swift`.

**Interfaces:**
- Produces: `struct PostCorrector: Sendable { init(store: CorrectionProfileStore); func correct(_ text: String, engineId: String) -> String }`. Remplacement insensible à la casse, sur des frontières de mots, en préservant le reste du texte.

- [ ] **Step 1: Test (échoue)** — ajouter

```swift
    func test_postCorrector_replacesHeardWithCanonical_caseInsensitive() {
        let store = InMemoryCorrectionProfileStore()
        store.add(CorrectionRule(heard: "doi", replacement: "Dokploy"), for: "apple.local")
        let pc = PostCorrector(store: store)
        let out = pc.correct("On parle de Doi en prod.", engineId: "apple.local")
        XCTAssertEqual(out, "On parle de Dokploy en prod.")
    }
    func test_postCorrector_multiWordHeard() {
        let store = InMemoryCorrectionProfileStore()
        store.add(CorrectionRule(heard: "doc ploy", replacement: "Dokploy"), for: "elevenlabs.scribe")
        let pc = PostCorrector(store: store)
        XCTAssertEqual(pc.correct("déployer sur Doc Ploy demain", engineId: "elevenlabs.scribe"),
                       "déployer sur Dokploy demain")
    }
    func test_postCorrector_noRules_returnsUnchanged() {
        let pc = PostCorrector(store: InMemoryCorrectionProfileStore())
        XCTAssertEqual(pc.correct("rien à corriger", engineId: "x"), "rien à corriger")
    }
```

- [ ] **Step 2: RED**.

- [ ] **Step 3: `PostCorrector.swift`**

```swift
import Foundation

public struct PostCorrector: Sendable {
    private let store: CorrectionProfileStore
    public init(store: CorrectionProfileStore) { self.store = store }

    public func correct(_ text: String, engineId: String) -> String {
        var result = text
        // Règles les plus longues d'abord (les phrases avant les mots isolés).
        let rules = store.rules(for: engineId).sorted { $0.heard.count > $1.heard.count }
        for rule in rules {
            result = replace(rule.heard, with: rule.replacement, in: result)
        }
        return result
    }

    /// Remplacement insensible à la casse, ancré sur des frontières de mots.
    private func replace(_ heard: String, with replacement: String, in text: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: heard)
        guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b", options: [.caseInsensitive]) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
    }
}
```

- [ ] **Step 4: GREEN**.
- [ ] **Step 5: Commit** — `feat(m3): PostCorrector (remplacement déterministe par moteur)`.

---

### Task 4: `GlossaryStore`

**Files:** Create `GlossaryStore.swift` ; Test `GlossaryStoreTests.swift`.

**Interfaces:**
- Produces: `protocol GlossaryStore: Sendable { var terms: [String] { get }; func add(_ term: String); func remove(_ term: String) }` ; `InMemoryGlossaryStore` ; `JSONGlossaryStore(url:)`.

- [ ] **Step 1: Test (échoue)**

```swift
import XCTest
@testable import FlowScribeCore

final class GlossaryStoreTests: XCTestCase {
    func test_addRemove_dedupCaseInsensitive() {
        let g = InMemoryGlossaryStore()
        g.add("Dokploy"); g.add("dokploy"); g.add("SwiftUI")
        XCTAssertEqual(g.terms.count, 2)
        g.remove("dokploy")
        XCTAssertEqual(g.terms, ["SwiftUI"])
    }
}
```

- [ ] **Step 2: RED**.

- [ ] **Step 3: `GlossaryStore.swift`**

```swift
import Foundation

public protocol GlossaryStore: Sendable {
    var terms: [String] { get }
    func add(_ term: String)
    func remove(_ term: String)
}

public final class InMemoryGlossaryStore: GlossaryStore, @unchecked Sendable {
    private var storage: [String] = []
    private let lock = NSLock()
    public init() {}
    public var terms: [String] { lock.lock(); defer { lock.unlock() }; return storage }
    public func add(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        if !storage.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) { storage.append(t) }
    }
    public func remove(_ term: String) {
        lock.lock(); defer { lock.unlock() }
        storage.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }
    }
}

public final class JSONGlossaryStore: GlossaryStore, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    private var storage: [String]
    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode([String].self, from: data) {
            storage = decoded
        } else { storage = [] }
    }
    public var terms: [String] { lock.lock(); defer { lock.unlock() }; return storage }
    public func add(_ term: String) {
        let t = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        lock.lock()
        if !storage.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) { storage.append(t) }
        lock.unlock(); persist()
    }
    public func remove(_ term: String) {
        lock.lock(); storage.removeAll { $0.caseInsensitiveCompare(term) == .orderedSame }; lock.unlock(); persist()
    }
    private func persist() {
        lock.lock(); let snap = storage; lock.unlock()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(snap) { try? data.write(to: url) }
    }
}
```

- [ ] **Step 4: GREEN**.
- [ ] **Step 5: Commit** — `feat(m3): GlossaryStore (termes, JSON + in-memory)`.

---

### Task 5: `CalibrationService` (proposition de règles)

**Files:** Create `CalibrationService.swift` ; Test `CalibrationServiceTests.swift`.

**Interfaces:**
- Consumes: `Aligner`, `CorrectionRule`.
- Produces: `enum CalibrationService { static func proposeRules(reference: String, hypothesis: String, glossary: [String]) -> [CorrectionRule] }`. Pour chaque terme du glossaire présent dans la référence, capte la portion d'hypothèse alignée (sub + insertions adjacentes) comme « entendu », et propose `heard -> terme canonique`.

- [ ] **Step 1: Test (échoue)**

```swift
import XCTest
@testable import FlowScribeCore

final class CalibrationServiceTests: XCTestCase {
    func test_proposes_singleTokenMishearing() {
        let rules = CalibrationService.proposeRules(
            reference: "On parle de Dokploy aujourd'hui.",
            hypothesis: "On parle de Doi aujourd'hui.",
            glossary: ["Dokploy"])
        XCTAssertEqual(rules, [CorrectionRule(heard: "doi", replacement: "Dokploy")])
    }
    func test_proposes_multiTokenMishearing() {
        let rules = CalibrationService.proposeRules(
            reference: "déployer sur Dokploy",
            hypothesis: "déployer sur Doc Ploy",
            glossary: ["Dokploy"])
        XCTAssertEqual(rules, [CorrectionRule(heard: "doc ploy", replacement: "Dokploy")])
    }
    func test_ignoresNonGlossaryDifferences() {
        let rules = CalibrationService.proposeRules(
            reference: "bonjour le monde",
            hypothesis: "bonsoir le monde",
            glossary: ["Dokploy"])
        XCTAssertTrue(rules.isEmpty)
    }
}
```

- [ ] **Step 2: RED**.

- [ ] **Step 3: `CalibrationService.swift`**

```swift
import Foundation

public enum CalibrationService {
    public static func proposeRules(reference: String, hypothesis: String, glossary: [String]) -> [CorrectionRule] {
        let refTokens = Aligner.tokenize(reference)
        let hypTokens = Aligner.tokenize(hypothesis)
        let pairs = Aligner.align(reference: refTokens, hypothesis: hypTokens)
        let canonical = Dictionary(glossary.map { ($0.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })

        var rules: [CorrectionRule] = []
        var idx = 0
        while idx < pairs.count {
            let pair = pairs[idx]
            // Un terme du glossaire dans la référence, mal entendu (substitution) ?
            if let ref = pair.reference, let term = canonical[ref], let firstHyp = pair.hypothesis, ref != firstHyp {
                var heardTokens = [firstHyp]
                // Capter les insertions adjacentes (ref nil) = mot scindé ("doc" + "ploy").
                var k = idx + 1
                while k < pairs.count, pairs[k].reference == nil, let h = pairs[k].hypothesis {
                    heardTokens.append(h); k += 1
                }
                rules.append(CorrectionRule(heard: heardTokens.joined(separator: " "), replacement: term))
                idx = k; continue
            }
            idx += 1
        }
        return rules
    }
}
```

- [ ] **Step 4: GREEN**.
- [ ] **Step 5: Commit** — `feat(m3): CalibrationService (propose des règles par alignement, ciblé glossaire)`.

---

### Task 6: Brancher la post-correction dans `TranscriptionService`

**Files:** Modify `TranscriptionService.swift` ; Test étend `TranscriptionServiceTests.swift`.

**Interfaces:**
- Consumes: `PostCorrector`.
- Produces: `TranscriptionService.init(primary:fallback:timeoutSeconds:postCorrector:)` (postCorrector optionnel) ; la post-correction est appliquée au texte selon l'`engineId` qui a réussi, avant de renvoyer `.success`.

- [ ] **Step 1: Test (échoue)** — ajouter

```swift
    func test_appliesPostCorrection_forSucceedingEngine() async {
        let store = InMemoryCorrectionProfileStore()
        store.add(CorrectionRule(heard: "doi", replacement: "Dokploy"), for: "p")
        let service = TranscriptionService(
            primary: MockEngine(id: "p", result: "On déploie Doi ce soir"),
            fallback: MockEngine(id: "apple", result: "x"),
            postCorrector: PostCorrector(store: store))
        let out = await service.transcribe(fileAt: URL(filePath: "/tmp/x.caf"), locale: .current)
        XCTAssertEqual(out, .success(text: "On déploie Dokploy ce soir", engineId: "p", usedFallback: false))
    }
```

- [ ] **Step 2: RED**.

- [ ] **Step 3: Modifier `TranscriptionService.swift`** — ajouter la propriété + l'application

Ajouter `private let postCorrector: PostCorrector?` et au init `postCorrector: PostCorrector? = nil`. Dans `transcribe`, remplacer les `return .success(text: text, ...)` par une version corrigée :
```swift
    public func transcribe(fileAt url: URL, locale: Locale) async -> TranscriptionOutcome {
        if let text = await tryEngine(primary, url: url, locale: locale) {
            return .success(text: corrected(text, primary.id), engineId: primary.id, usedFallback: false)
        }
        if primary.id != fallback.id, let text = await tryEngine(fallback, url: url, locale: locale) {
            return .success(text: corrected(text, fallback.id), engineId: fallback.id, usedFallback: true)
        }
        return .failed
    }

    private func corrected(_ text: String, _ engineId: String) -> String {
        postCorrector?.correct(text, engineId: engineId) ?? text
    }
```

- [ ] **Step 4: GREEN** — `swift test` (toute la suite verte).
- [ ] **Step 5: Commit** — `feat(m3): post-correction par moteur branchée dans TranscriptionService`.

---

### Task 7: UI — Glossaire & corrections (Réglages)

**Files:** Create `FlowScribe/GlossaryView.swift` ; Modify `FlowScribe/SettingsView.swift` (ajouter une section/onglet « Glossaire »).

**Interfaces:**
- Consumes: `GlossaryStore`, `CorrectionProfileStore`, `EngineProvider`.
- Produces: `GlossaryView` (ajout/suppression de termes ; liste des règles de correction par moteur avec suppression). Les stores JSON sont créés dans `FlowScribeApp` (Application Support) et injectés.

> UI : validée par build + run manuel.

- [ ] **Step 1: Écrire `GlossaryView.swift`** (liste de termes éditable + règles par moteur). Code complet :

```swift
import SwiftUI
import FlowScribeCore

@MainActor
@Observable
final class GlossaryViewModel {
    let glossary: GlossaryStore
    let profiles: CorrectionProfileStore
    var terms: [String] = []
    var newTerm: String = ""

    init(glossary: GlossaryStore, profiles: CorrectionProfileStore) {
        self.glossary = glossary; self.profiles = profiles; refresh()
    }
    func refresh() { terms = glossary.terms }
    func addTerm() { glossary.add(newTerm); newTerm = ""; refresh() }
    func removeTerm(_ t: String) { glossary.remove(t); refresh() }
    func rules(for provider: EngineProvider) -> [CorrectionRule] { profiles.rules(for: engineId(provider)) }
    func engineId(_ p: EngineProvider) -> String { p.config?.id ?? "apple.local" }
}

struct GlossaryView: View {
    @Bindable var model: GlossaryViewModel
    var body: some View {
        Form {
            Section("Termes du glossaire") {
                HStack {
                    TextField("Nouveau terme (ex. Dokploy)", text: $model.newTerm)
                    Button("Ajouter") { model.addTerm() }.buttonStyle(.glass)
                }
                ForEach(model.terms, id: \.self) { t in
                    HStack { Text(t); Spacer(); Button(role: .destructive) { model.removeTerm(t) } label: { Image(systemName: "trash") } }
                }
            }
            Section("Corrections apprises (par moteur)") {
                ForEach(EngineProvider.allCases, id: \.self) { p in
                    let rules = model.rules(for: p)
                    if !rules.isEmpty {
                        Text(p.displayName).font(.headline)
                        ForEach(rules, id: \.heard) { r in
                            Text("« \(r.heard) » → \(r.replacement)").font(.caption)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped).frame(width: 470, height: 460)
        .onAppear { model.refresh() }
    }
}
```

- [ ] **Step 2: Brancher dans l'app** — dans `FlowScribeApp`, créer les stores JSON (Application Support) et exposer `GlossaryView` (nouvelle fenêtre `Window("Glossaire", id: "glossary")` ou section dans Settings). Build : `xcodegen generate && xcodebuild ... build` → SUCCEEDED.
- [ ] **Step 3: Commit** — `feat(m3): éditeur de glossaire & corrections (UI)`.

---

### Task 8: UI — Calibration par lecture + branchement pipeline

**Files:** Create `FlowScribe/CalibrationView.swift` ; Modify `FlowScribe/FlowScribeApp.swift` (créer les stores, injecter `PostCorrector` dans le service, ajouter la fenêtre Calibration).

**Interfaces:**
- Consumes: `AudioRecorder` (MicrophoneRecorder), moteur courant, `CalibrationService`, `GlossaryStore`, `CorrectionProfileStore`.
- Produces: `CalibrationView` : affiche un texte de référence (généré depuis le glossaire), bouton Enregistrer/Stop, transcrit via le moteur courant, montre les `CorrectionRule` proposées, l'utilisateur **accepte** → `profiles.add(rule, for: engineId)`. Et `FlowScribeApp` injecte `PostCorrector(store:)` dans `makeService` pour que les dictées normales soient corrigées.

> UI + audio : validée par build + recette manuelle.

- [ ] **Step 1: Injecter `PostCorrector` dans `makeService`** (`FlowScribeApp`) :
```swift
    @MainActor
    private static func makeService(from settings: SettingsStore, profiles: CorrectionProfileStore) -> TranscriptionService {
        let transport = URLSessionTransport()
        let apple = AppleSpeechEngine()
        let provider = settings.defaultProvider
        let primary = provider.makeEngine(apiKey: settings.apiKey(for: provider), transport: transport) ?? apple
        return TranscriptionService(primary: primary, fallback: apple, postCorrector: PostCorrector(store: profiles))
    }
```
(et passer `profiles` depuis un `@State` créé avec `JSONCorrectionProfileStore(url: ApplicationSupport/FlowScribe/corrections.json)`).

- [ ] **Step 2: Écrire `CalibrationView.swift`** — texte de référence (jointure de phrases contenant les termes du glossaire), enregistrement via `MicrophoneRecorder`, transcription via le moteur courant, `CalibrationService.proposeRules(...)`, liste de cases à cocher, bouton « Enregistrer les corrections » → `profiles.add`. (Code complet à écrire ; réutilise `MicrophoneRecorder` + `EngineProvider.makeEngine`.)

- [ ] **Step 3: Build** — `xcodegen generate && xcodebuild ... build` → SUCCEEDED.
- [ ] **Step 4: Recette manuelle (PORTE HUMAINE)** : ajouter « Dokploy » au glossaire, lancer une calibration (lire la phrase), accepter la règle proposée, puis dicter « Dokploy » normalement → le texte collé doit afficher « Dokploy » corrigé.
- [ ] **Step 5: Commit** — `feat(m3): calibration par lecture + post-correction branchée`.

---

## Auto-revue (faite à l'écriture)

- **Couverture M3** : Aligner (T1), profils par moteur (T2), PostCorrector (T3), glossaire (T4), CalibrationService (T5), branchement pipeline (T6), UI glossaire (T7), UI calibration + injection (T8). ✅
- **Différé M3b** : keyterms natifs par fournisseur (API à confirmer), passe IA de proposition, import de document → extraction. Noté hors M3.
- **Placeholders** : T1-T6 ont du code complet ; T7 code complet ; T8 décrit `CalibrationView` à écrire (UI, validée build+manuel) — seule partie sans code intégral, car dépend du câblage audio réel.
- **Cohérence types** : `AlignedPair`, `CorrectionRule(heard,replacement)`, `CorrectionProfileStore.rules(for:)`, `PostCorrector.correct(_:engineId:)`, `CalibrationService.proposeRules(reference:hypothesis:glossary:)`, `TranscriptionService(...postCorrector:)` cohérents.

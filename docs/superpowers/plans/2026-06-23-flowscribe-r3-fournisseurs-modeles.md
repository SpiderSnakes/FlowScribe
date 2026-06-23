# R3 — Fournisseurs → modèles & switch rapide — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development ou executing-plans. (Cette session : exécution inline.)

**Goal:** Choix du modèle par fournisseur (clé + modèle) et bascule rapide du moteur/modèle actif sur l'Accueil.

**Architecture:** `EngineModel` + `EngineProvider.models`/`defaultModelId` côté core ; `makeEngine(apiKey:modelId:transport:)` et `CloudTranscriptionEngine(...modelId:)` utilisent le modèle choisi ; `SettingsStore` persiste le modèle par fournisseur ; Réglages = picker modèle ; Accueil = menu de bascule.

**Tech Stack:** Swift 6, FlowScribeCore (SPM), SwiftUI, XCTest.

## Global Constraints
- macOS 26+, Apple Silicon, Swift 6.
- Modèles (juin 2026) : Apple `apple` · ElevenLabs `scribe_v2` · Mistral `voxtral-mini-latest` · OpenAI `gpt-4o-transcribe`/`gpt-4o-mini-transcribe`/`whisper-1`.
- `modelId` nil ⇒ `provider.defaultModelId` (pas de rupture des appels existants).
- Cœur (models, makeEngine, CloudTranscriptionEngine modelId) = **TDD** ; UI = build + recette.
- Commits fréquents (français + trailer), push sur `origin r3-fournisseurs-modeles`.

## Structure
```
FlowScribeCore/Sources/FlowScribeCore/
├── EngineProvider.swift            (modifié) EngineModel + models + defaultModelId + makeEngine(modelId:)
├── CloudTranscriptionEngine.swift  (modifié) init(...modelId:) ; modelId prime sur config.modelValue
FlowScribe/
├── SettingsStore.swift             (modifié) selectedModelId(for:) / setModel(_:for:)
├── SettingsView.swift              (modifié) Picker de modèle par fournisseur
├── HomeView.swift                  (modifié) menu de bascule fournisseur+modèle
└── FlowScribeApp.swift             (modifié) makeService/retranscribe utilisent le modèle sélectionné
```

---

### Task 1: `EngineModel` + modèles + `makeEngine(modelId:)` (cœur, TDD)
**Files:** Modify `EngineProvider.swift`, `CloudTranscriptionEngine.swift` ; Test `EngineProviderTests.swift`, `CloudTranscriptionEngineTests.swift` (ajouts).
**Interfaces:**
- Produces: `struct EngineModel: Equatable, Sendable { let id: String; let displayName: String }` ; `EngineProvider.models: [EngineModel]` ; `EngineProvider.defaultModelId: String` ; `EngineProvider.makeEngine(apiKey:modelId:transport:)` (modelId par défaut nil) ; `CloudTranscriptionEngine(config:apiKey:transport:modelId:)`.

- [ ] **Step 1: Tests (échouent)** — ajouter à `EngineProviderTests.swift`
```swift
    func test_models_perProvider() {
        XCTAssertEqual(EngineProvider.elevenLabs.models.map(\.id), ["scribe_v2"])
        XCTAssertEqual(EngineProvider.mistral.models.map(\.id), ["voxtral-mini-latest"])
        XCTAssertEqual(EngineProvider.openAI.models.map(\.id),
                       ["gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"])
        XCTAssertEqual(EngineProvider.openAI.defaultModelId, "gpt-4o-transcribe")
        XCTAssertEqual(EngineProvider.appleLocal.models.count, 1)
    }
    func test_makeEngine_withModelId_buildsCloudEngine() {
        let e = EngineProvider.openAI.makeEngine(apiKey: "sk", modelId: "whisper-1", transport: MockTransport())
        XCTAssertEqual(e?.id, CloudEngineConfig.openAI.id)
    }
```
  et à `CloudTranscriptionEngineTests.swift` :
```swift
    func test_transcribeFile_usesModelOverride() async throws {
        let mock = MockTransport(statusCode: 200, body: Data(#"{"text":"x"}"#.utf8))
        let engine = CloudTranscriptionEngine(config: .openAI, apiKey: "k", transport: mock, modelId: "whisper-1")
        let url = FileManager.default.temporaryDirectory.appending(path: "m.wav")
        try Data("RIFF".utf8).write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        _ = try await engine.transcribeFile(at: url, locale: .current)
        let body = String(decoding: mock.lastRequest?.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("whisper-1"))
        XCTAssertFalse(body.contains("gpt-4o-transcribe"))
    }
```
- [ ] **Step 2: RED** — `cd FlowScribeCore && swift test --filter EngineProviderTests` + `--filter CloudTranscriptionEngineTests`.
- [ ] **Step 3: `CloudTranscriptionEngine`** — ajouter `modelId`. Modifier l'init et l'usage :
```swift
    private let modelId: String?
    public init(config: CloudEngineConfig, apiKey: String, transport: Transport, boundary: String = "FlowScribeBoundary", modelId: String? = nil) {
        self.config = config; self.apiKey = apiKey; self.transport = transport; self.boundary = boundary; self.modelId = modelId
    }
    private var effectiveModel: String { modelId ?? config.modelValue }
```
  Dans `transcribeFile` et `validateKey`, remplacer `form.addField(name: config.modelField, value: config.modelValue)` par `form.addField(name: config.modelField, value: effectiveModel)`.
- [ ] **Step 4: `EngineProvider`** — ajouter `EngineModel`, `models`, `defaultModelId`, et étendre `makeEngine` :
```swift
public struct EngineModel: Equatable, Sendable {
    public let id: String
    public let displayName: String
    public init(id: String, displayName: String) { self.id = id; self.displayName = displayName }
}

extension EngineProvider {
    public var models: [EngineModel] {
        switch self {
        case .appleLocal: return [EngineModel(id: "apple", displayName: "Apple — sur l'appareil")]
        case .elevenLabs: return [EngineModel(id: "scribe_v2", displayName: "Scribe v2")]
        case .mistral:    return [EngineModel(id: "voxtral-mini-latest", displayName: "Voxtral Mini Transcribe")]
        case .openAI:     return [EngineModel(id: "gpt-4o-transcribe", displayName: "GPT-4o Transcribe"),
                                  EngineModel(id: "gpt-4o-mini-transcribe", displayName: "GPT-4o mini Transcribe"),
                                  EngineModel(id: "whisper-1", displayName: "Whisper (legacy)")]
        }
    }
    public var defaultModelId: String { models.first?.id ?? "" }
}
```
  Et remplacer `makeEngine` :
```swift
    public func makeEngine(apiKey: String?, modelId: String? = nil, transport: Transport) -> TranscriptionEngine? {
        if self == .appleLocal { return AppleSpeechEngine() }
        guard let config, let apiKey, !apiKey.isEmpty else { return nil }
        return CloudTranscriptionEngine(config: config, apiKey: apiKey, transport: transport, modelId: modelId ?? defaultModelId)
    }
```
- [ ] **Step 5: GREEN** (`swift test`) ; **Commit** `feat(r3): EngineModel + modèles par fournisseur + makeEngine(modelId:)`.

---

### Task 2: Réglages — modèle par fournisseur
**Files:** Modify `SettingsStore.swift`, `SettingsView.swift`.
> Build + recette.

- [ ] **Step 1: `SettingsStore`** — ajouter :
```swift
    func selectedModelId(for provider: EngineProvider) -> String {
        defaults.string(forKey: "model.\(provider.rawValue)") ?? provider.defaultModelId
    }
    func setModel(_ id: String, for provider: EngineProvider) {
        defaults.set(id, forKey: "model.\(provider.rawValue)")
        onChange?()
    }
```
- [ ] **Step 2: `SettingsView`** — dans la section « Clés API », sous le `SecureField` de chaque fournisseur, ajouter un Picker de modèle (s'il y a >1 modèle) :
```swift
                ForEach(cloudProviders, id: \.self) { p in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            SecureField(p.displayName, text: draftBinding(p))
                            statusIcon(for: p)
                            Button("Tester") { test(p) }.disabled(testing.contains(p.secretKey ?? ""))
                        }
                        if p.models.count > 1 {
                            Picker("Modèle", selection: Binding(
                                get: { settings.selectedModelId(for: p) },
                                set: { settings.setModel($0, for: p) })) {
                                ForEach(p.models, id: \.id) { m in Text(m.displayName).tag(m.id) }
                            }
                        }
                        if let msg = message(for: p) {
                            Text(msg).font(.caption).foregroundStyle(resultColor(for: p))
                        }
                    }
                }
```
- [ ] **Step 3: Build** → SUCCEEDED ; **Commit** `feat(r3): sélecteur de modèle par fournisseur (Réglages)`.

---

### Task 3: Accueil — bascule rapide fournisseur + modèle (PORTE HUMAINE)
**Files:** Modify `HomeView.swift`, `FlowScribeApp.swift`.
> Build + recette.

- [ ] **Step 1: `FlowScribeApp.makeService`** — utiliser le modèle sélectionné :
```swift
    @MainActor
    private static func makeService(from settings: SettingsStore, profiles: CorrectionProfileStore) -> TranscriptionService {
        let transport = URLSessionTransport()
        let apple = AppleSpeechEngine()
        let provider = settings.defaultProvider
        let primary = provider.makeEngine(apiKey: settings.apiKey(for: provider),
                                           modelId: settings.selectedModelId(for: provider),
                                           transport: transport) ?? apple
        return TranscriptionService(primary: primary, fallback: apple, postCorrector: PostCorrector(store: profiles))
    }
```
  et `retranscribe(...)` : `provider.makeEngine(apiKey: settings.apiKey(for: provider), modelId: settings.selectedModelId(for: provider), transport: URLSessionTransport())`.
- [ ] **Step 2: `HomeView`** — remplacer la pastille « Moteur : … » par un **menu** de bascule (passer `settings` permet de lire/écrire). Remplacer le `Text("Moteur : …")` par :
```swift
                Menu {
                    ForEach(EngineProvider.allCases, id: \.self) { p in
                        Menu(p.displayName) {
                            ForEach(p.models, id: \.id) { m in
                                Button(m.displayName) {
                                    settings.defaultProvider = p
                                    settings.setModel(m.id, for: p)
                                }
                            }
                        }
                    }
                } label: {
                    let p = settings.defaultProvider
                    let model = p.models.first { $0.id == settings.selectedModelId(for: p) }
                    Label("\(p.displayName) · \(model?.displayName ?? "")", systemImage: "cpu")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
```
  (`settings.defaultProvider`/`setModel` déclenchent `onChange` → service reconstruit à chaud.)
- [ ] **Step 3: Build** → SUCCEEDED.
- [ ] **Step 4: Recette (PORTE HUMAINE)** : Réglages → choisir un modèle OpenAI (ex. whisper-1) ; Accueil → le menu affiche le moteur+modèle, en changer → dicter → la transcription utilise le modèle choisi (vérifiable via l'historique/le moteur). Bascule entre fournisseurs sans relancer.
- [ ] **Step 5: Commit** `feat(r3): bascule rapide fournisseur+modèle sur l'Accueil`.

---

## Auto-revue (à l'écriture)
- **Couverture spec** : EngineModel + modèles (T1), makeEngine(modelId)/CloudTranscriptionEngine modelId (T1), persistance modèle + picker Réglages (T2), bascule Accueil + makeService (T3). ✅
- **Hors R3** : Fichiers (R4), règles (R5), motion (R6), diarize/realtime.
- **Placeholders** : aucun ; T1 code+tests complets ; T2/T3 code complet.
- **Cohérence types** : `EngineModel(id:displayName:)`, `EngineProvider.models/defaultModelId/makeEngine(apiKey:modelId:transport:)`, `CloudTranscriptionEngine(...modelId:)`, `SettingsStore.selectedModelId(for:)/setModel(_:for:)` cohérents ; `makeEngine` modelId par défaut nil → pas de rupture (SettingsView.test(), tests existants).

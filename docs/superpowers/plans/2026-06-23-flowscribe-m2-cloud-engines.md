# FlowScribe — M2 Moteurs cloud & BYO-key — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax. (Cette session : exécution inline car le dispatch de sous-agents est tombé en panne.)

**Goal:** Permettre la dictée via les moteurs cloud (ElevenLabs Scribe, Mistral Voxtral, OpenAI gpt-4o-transcribe) avec tes propres clés (Keychain), sélection du moteur par défaut, repli automatique sur Apple local en cas d'échec réseau, et estimation de coût.

**Architecture:** Un **unique** `CloudTranscriptionEngine` configurable (DRY) couvre les 3 providers via un `CloudEngineConfig` (endpoint, en-tête d'auth, champ modèle, prix/min). Le réseau passe par un protocole `Transport` injectable → la construction de requête et le parsing sont testables avec un `MockTransport`, sans réseau réel. Les clés vivent derrière `SecretStore` (Keychain en prod, in-memory en test). `TranscriptionService` choisit le moteur et retombe sur `AppleSpeechEngine` (M1) si le cloud échoue.

**Tech Stack:** Swift 6, FlowScribeCore (SPM), URLSession, Security (Keychain), SwiftUI (réglages), XCTest.

## Global Constraints

- Plateforme **macOS 26.0+**, Apple Silicon, **Swift 6** (concurrence stricte).
- **BYO-key** : les clés API ne vivent QUE dans le Keychain ; jamais dans le repo, les logs, ou UserDefaults.
- Moteurs cloud **batch** (fichier) en M2 ; le streaming live est différé.
- Tout le réseau passe par `Transport` (injectable) → tests sans réseau réel via `MockTransport`.
- Repli systématique : si le moteur cloud échoue, `TranscriptionService` transcrit le fichier sauvegardé via Apple local (jamais bloqué — pilier #1).
- Logique métier dans `FlowScribeCore` (testée `swift test`) ; l'app ne fait que câbler + UI.
- Commits fréquents (français + trailer Co-Authored-By), push sur `origin m2-persistence-cloud` après chaque tâche.
- IDs de modèles / endpoints retenus (à confirmer vs docs officielles à l'intégration) : OpenAI `gpt-4o-transcribe` @ `https://api.openai.com/v1/audio/transcriptions` (Bearer) ; Mistral `voxtral-mini-latest` @ `https://api.mistral.ai/v1/audio/transcriptions` (Bearer) ; ElevenLabs `scribe_v1` @ `https://api.elevenlabs.io/v1/speech-to-text` (en-tête `xi-api-key`).

---

## Structure de fichiers

```
FlowScribeCore/Sources/FlowScribeCore/
├── Transport.swift              protocole Transport + URLSessionTransport
├── SecretStore.swift            protocole SecretStore + InMemorySecretStore + KeychainSecretStore
├── MultipartFormData.swift      constructeur multipart (pur, testable)
├── CloudEngineConfig.swift      struct config + configs openAI/mistral/elevenLabs
├── CloudTranscriptionEngine.swift  moteur cloud générique (transcribeFile via Transport)
├── EngineProvider.swift         enum providers + factory (provider+clé+transport -> TranscriptionEngine)
├── TranscriptionService.swift   sélection + fallback Apple local
└── CostEstimator.swift          estimation coût (durée × prix/min)
FlowScribeCore/Tests/FlowScribeCoreTests/
├── MultipartFormDataTests.swift
├── CloudTranscriptionEngineTests.swift
├── EngineProviderTests.swift
├── TranscriptionServiceTests.swift
└── CostEstimatorTests.swift
FlowScribe/
├── SettingsStore.swift          @Observable : provider par défaut + langue (UserDefaults)
├── SettingsView.swift           saisie des clés (SecretStore) + choix moteur + langue
└── FlowScribeApp.swift          (modifié) onglet Réglages + DictationController via service
```

---

### Task 1: `Transport` + `MockTransport`

**Files:**
- Create: `FlowScribeCore/Sources/FlowScribeCore/Transport.swift`
- Test: `FlowScribeCore/Tests/FlowScribeCoreTests/CloudTranscriptionEngineTests.swift` (le MockTransport y sera réutilisé ; ce test initial le valide)

**Interfaces:**
- Produces: `protocol Transport: Sendable { func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) }` ; `struct URLSessionTransport: Transport` ; `final class MockTransport: Transport` (réponse programmable + capture de la dernière requête).

- [ ] **Step 1: Écrire le test (échoue)**

```swift
import XCTest
@testable import FlowScribeCore

final class CloudTranscriptionEngineTests: XCTestCase {
    func test_mockTransport_returnsCannedResponse_andCapturesRequest() async throws {
        let mock = MockTransport(statusCode: 200, body: Data("ok".utf8))
        var req = URLRequest(url: URL(string: "https://example.com")!)
        req.httpMethod = "POST"
        let (data, resp) = try await mock.send(req)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "ok")
        XCTAssertEqual(resp.statusCode, 200)
        XCTAssertEqual(mock.lastRequest?.httpMethod, "POST")
    }
}
```

- [ ] **Step 2: Lancer — RED**

Run: `cd FlowScribeCore && swift test --filter CloudTranscriptionEngineTests`
Expected: FAIL (`MockTransport`/`Transport` introuvable).

- [ ] **Step 3: Écrire `Transport.swift`**

```swift
import Foundation

public protocol Transport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: Transport {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

/// Transport de test : renvoie une réponse programmée et capture la requête.
public final class MockTransport: Transport, @unchecked Sendable {
    public private(set) var lastRequest: URLRequest?
    private let statusCode: Int
    private let body: Data
    private let error: Error?
    public init(statusCode: Int = 200, body: Data = Data(), error: Error? = nil) {
        self.statusCode = statusCode; self.body = body; self.error = error
    }
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        if let error { throw error }
        let resp = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        return (body, resp)
    }
}
```

- [ ] **Step 4: Lancer — GREEN**

Run: `cd FlowScribeCore && swift test --filter CloudTranscriptionEngineTests`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add FlowScribeCore && git commit -m "feat(m2): Transport + MockTransport" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && git push
```

---

### Task 2: `SecretStore` (Keychain + in-memory)

**Files:**
- Create: `FlowScribeCore/Sources/FlowScribeCore/SecretStore.swift`
- Test: `FlowScribeCore/Tests/FlowScribeCoreTests/SecretStoreTests.swift`

**Interfaces:**
- Produces: `protocol SecretStore: Sendable { func set(_ value: String?, for key: String) ; func get(_ key: String) -> String? }` ; `final class InMemorySecretStore` ; `final class KeychainSecretStore`.

- [ ] **Step 1: Écrire le test (échoue)**

```swift
import XCTest
@testable import FlowScribeCore

final class SecretStoreTests: XCTestCase {
    func test_inMemory_setGetDelete() {
        let store = InMemorySecretStore()
        XCTAssertNil(store.get("openai"))
        store.set("sk-123", for: "openai")
        XCTAssertEqual(store.get("openai"), "sk-123")
        store.set(nil, for: "openai")
        XCTAssertNil(store.get("openai"))
    }
}
```

- [ ] **Step 2: Lancer — RED**

Run: `cd FlowScribeCore && swift test --filter SecretStoreTests`
Expected: FAIL.

- [ ] **Step 3: Écrire `SecretStore.swift`**

```swift
import Foundation
import Security

public protocol SecretStore: Sendable {
    func set(_ value: String?, for key: String)
    func get(_ key: String) -> String?
}

/// Store en mémoire (tests).
public final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    private var storage: [String: String] = [:]
    private let lock = NSLock()
    public init() {}
    public func set(_ value: String?, for key: String) {
        lock.lock(); defer { lock.unlock() }
        if let value { storage[key] = value } else { storage[key] = nil }
    }
    public func get(_ key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }
}

/// Store Keychain (prod). `service` namespace les entrées de l'app.
public final class KeychainSecretStore: SecretStore, @unchecked Sendable {
    private let service: String
    public init(service: String = "cloud.spidersnake.FlowScribe") { self.service = service }

    public func set(_ value: String?, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    public func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
```

- [ ] **Step 4: Lancer — GREEN**

Run: `cd FlowScribeCore && swift test --filter SecretStoreTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add FlowScribeCore && git commit -m "feat(m2): SecretStore (Keychain + in-memory)" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && git push
```

---

### Task 3: `MultipartFormData` (constructeur pur)

**Files:**
- Create: `FlowScribeCore/Sources/FlowScribeCore/MultipartFormData.swift`
- Test: `FlowScribeCore/Tests/FlowScribeCoreTests/MultipartFormDataTests.swift`

**Interfaces:**
- Produces: `struct MultipartFormData { init(boundary: String) ; mutating func addField(name:value:) ; mutating func addFile(name:filename:contentType:data:) ; var contentType: String ; func encoded() -> Data }`.

- [ ] **Step 1: Écrire le test (échoue)**

```swift
import XCTest
@testable import FlowScribeCore

final class MultipartFormDataTests: XCTestCase {
    func test_buildsBodyWithFieldAndFile() {
        var form = MultipartFormData(boundary: "BOUNDARY")
        form.addField(name: "model", value: "gpt-4o-transcribe")
        form.addFile(name: "file", filename: "a.wav", contentType: "audio/wav", data: Data("RIFF".utf8))
        let body = String(decoding: form.encoded(), as: UTF8.self)
        XCTAssertEqual(form.contentType, "multipart/form-data; boundary=BOUNDARY")
        XCTAssertTrue(body.contains("name=\"model\""))
        XCTAssertTrue(body.contains("gpt-4o-transcribe"))
        XCTAssertTrue(body.contains("filename=\"a.wav\""))
        XCTAssertTrue(body.contains("Content-Type: audio/wav"))
        XCTAssertTrue(body.hasSuffix("--BOUNDARY--\r\n"))
    }
}
```

- [ ] **Step 2: Lancer — RED**

Run: `cd FlowScribeCore && swift test --filter MultipartFormDataTests`
Expected: FAIL.

- [ ] **Step 3: Écrire `MultipartFormData.swift`**

```swift
import Foundation

public struct MultipartFormData {
    private let boundary: String
    private var body = Data()
    public init(boundary: String) { self.boundary = boundary }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    public mutating func addFile(name: String, filename: String, contentType: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    public func encoded() -> Data {
        var out = body
        out.append(Data("--\(boundary)--\r\n".utf8))
        return out
    }

    private mutating func append(_ string: String) { body.append(Data(string.utf8)) }
}
```

- [ ] **Step 4: Lancer — GREEN**

Run: `cd FlowScribeCore && swift test --filter MultipartFormDataTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add FlowScribeCore && git commit -m "feat(m2): constructeur MultipartFormData (pur)" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && git push
```

---

### Task 4: `CloudEngineConfig` + configs des 3 providers

**Files:**
- Create: `FlowScribeCore/Sources/FlowScribeCore/CloudEngineConfig.swift`
- Test: `FlowScribeCore/Tests/FlowScribeCoreTests/EngineProviderTests.swift` (vérifie les valeurs des configs)

**Interfaces:**
- Produces: `struct CloudEngineConfig: Sendable` (id, endpoint, authHeaderName, authValuePrefix, modelField, modelValue, capabilities, pricePerMinuteUSD) ; statics `.openAI`, `.mistral`, `.elevenLabs`.

- [ ] **Step 1: Écrire le test (échoue)**

```swift
import XCTest
@testable import FlowScribeCore

final class EngineProviderTests: XCTestCase {
    func test_configs_haveExpectedAuthAndModelFields() {
        XCTAssertEqual(CloudEngineConfig.openAI.authHeaderName, "Authorization")
        XCTAssertEqual(CloudEngineConfig.openAI.modelField, "model")
        XCTAssertEqual(CloudEngineConfig.elevenLabs.authHeaderName, "xi-api-key")
        XCTAssertEqual(CloudEngineConfig.elevenLabs.modelField, "model_id")
        XCTAssertEqual(CloudEngineConfig.mistral.authValuePrefix, "Bearer ")
        XCTAssertTrue(CloudEngineConfig.openAI.pricePerMinuteUSD > 0)
    }
}
```

- [ ] **Step 2: Lancer — RED**

Run: `cd FlowScribeCore && swift test --filter EngineProviderTests`
Expected: FAIL.

- [ ] **Step 3: Écrire `CloudEngineConfig.swift`**

```swift
import Foundation

public struct CloudEngineConfig: Sendable {
    public let id: String
    public let endpoint: URL
    public let authHeaderName: String
    public let authValuePrefix: String
    public let modelField: String
    public let modelValue: String
    public let capabilities: EngineCapabilities
    public let pricePerMinuteUSD: Double

    // IDs/endpoints à confirmer vs docs officielles (cf. Global Constraints).
    public static let openAI = CloudEngineConfig(
        id: "openai.gpt-4o-transcribe",
        endpoint: URL(string: "https://api.openai.com/v1/audio/transcriptions")!,
        authHeaderName: "Authorization", authValuePrefix: "Bearer ",
        modelField: "model", modelValue: "gpt-4o-transcribe",
        capabilities: EngineCapabilities(supportsStreaming: false, supportsKeyterms: false, isLocal: false),
        pricePerMinuteUSD: 0.006)

    public static let mistral = CloudEngineConfig(
        id: "mistral.voxtral",
        endpoint: URL(string: "https://api.mistral.ai/v1/audio/transcriptions")!,
        authHeaderName: "Authorization", authValuePrefix: "Bearer ",
        modelField: "model", modelValue: "voxtral-mini-latest",
        capabilities: EngineCapabilities(supportsStreaming: false, supportsKeyterms: false, isLocal: false),
        pricePerMinuteUSD: 0.003)

    public static let elevenLabs = CloudEngineConfig(
        id: "elevenlabs.scribe",
        endpoint: URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!,
        authHeaderName: "xi-api-key", authValuePrefix: "",
        modelField: "model_id", modelValue: "scribe_v1",
        capabilities: EngineCapabilities(supportsStreaming: false, supportsKeyterms: true, isLocal: false),
        pricePerMinuteUSD: 0.0066)
}
```

- [ ] **Step 4: Lancer — GREEN**

Run: `cd FlowScribeCore && swift test --filter EngineProviderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add FlowScribeCore && git commit -m "feat(m2): CloudEngineConfig + configs OpenAI/Mistral/ElevenLabs" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && git push
```

---

### Task 5: `CloudTranscriptionEngine` (transcribeFile via Transport)

**Files:**
- Create: `FlowScribeCore/Sources/FlowScribeCore/CloudTranscriptionEngine.swift`
- Test: `FlowScribeCore/Tests/FlowScribeCoreTests/CloudTranscriptionEngineTests.swift` (étendre)

**Interfaces:**
- Consumes: `Transport`, `CloudEngineConfig`, `MultipartFormData`, `TranscriptionEngine`.
- Produces: `final class CloudTranscriptionEngine: TranscriptionEngine` (init `config:apiKey:transport:boundary:`).

- [ ] **Step 1: Étendre le test (échoue)** — ajouter dans `CloudTranscriptionEngineTests`

```swift
    func test_transcribeFile_buildsAuthorizedMultipartPost_andParsesText() async throws {
        let mock = MockTransport(statusCode: 200, body: Data(#"{"text":"bonjour"}"#.utf8))
        let engine = CloudTranscriptionEngine(config: .openAI, apiKey: "sk-123", transport: mock, boundary: "B")
        let url = FileManager.default.temporaryDirectory.appending(path: "clip.wav")
        try Data("RIFFDATA".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try await engine.transcribeFile(at: url, locale: Locale(identifier: "fr-FR"))

        XCTAssertEqual(text, "bonjour")
        let req = try XCTUnwrap(mock.lastRequest)
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url, CloudEngineConfig.openAI.endpoint)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-123")
        XCTAssertTrue(req.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") ?? false)
        let body = String(decoding: req.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("gpt-4o-transcribe"))
        XCTAssertTrue(body.contains("filename=\"clip.wav\""))
    }

    func test_transcribeFile_throwsOnHTTPError() async {
        let mock = MockTransport(statusCode: 401, body: Data(#"{"error":"unauthorized"}"#.utf8))
        let engine = CloudTranscriptionEngine(config: .openAI, apiKey: "bad", transport: mock, boundary: "B")
        let url = FileManager.default.temporaryDirectory.appending(path: "c2.wav")
        try? Data("x".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        do { _ = try await engine.transcribeFile(at: url, locale: .current); XCTFail("devrait lever") }
        catch { /* attendu */ }
    }
```

- [ ] **Step 2: Lancer — RED**

Run: `cd FlowScribeCore && swift test --filter CloudTranscriptionEngineTests`
Expected: FAIL (`CloudTranscriptionEngine` introuvable).

- [ ] **Step 3: Écrire `CloudTranscriptionEngine.swift`**

```swift
import Foundation

public enum CloudTranscriptionError: Error { case httpError(status: Int, body: String), badResponse }

public final class CloudTranscriptionEngine: TranscriptionEngine {
    public var id: String { config.id }
    public var capabilities: EngineCapabilities { config.capabilities }

    private let config: CloudEngineConfig
    private let apiKey: String
    private let transport: Transport
    private let boundary: String

    public init(config: CloudEngineConfig, apiKey: String, transport: Transport, boundary: String = "FlowScribeBoundary") {
        self.config = config; self.apiKey = apiKey; self.transport = transport; self.boundary = boundary
    }

    public func transcribeFile(at url: URL, locale: Locale) async throws -> String {
        let audio = try Data(contentsOf: url)
        var form = MultipartFormData(boundary: boundary)
        form.addField(name: config.modelField, value: config.modelValue)
        form.addFile(name: "file", filename: url.lastPathComponent, contentType: "audio/wav", data: audio)

        var request = URLRequest(url: config.endpoint)
        request.httpMethod = "POST"
        request.setValue("\(config.authValuePrefix)\(apiKey)", forHTTPHeaderField: config.authHeaderName)
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.encoded()

        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw CloudTranscriptionError.httpError(status: response.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj["text"] as? String else {
            throw CloudTranscriptionError.badResponse
        }
        return text
    }
}
```

- [ ] **Step 4: Lancer — GREEN**

Run: `cd FlowScribeCore && swift test --filter CloudTranscriptionEngineTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add FlowScribeCore && git commit -m "feat(m2): CloudTranscriptionEngine (multipart POST via Transport)" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && git push
```

---

### Task 6: `EngineProvider` + factory

**Files:**
- Create: `FlowScribeCore/Sources/FlowScribeCore/EngineProvider.swift`
- Test: `FlowScribeCore/Tests/FlowScribeCoreTests/EngineProviderTests.swift` (étendre)

**Interfaces:**
- Consumes: `CloudEngineConfig`, `CloudTranscriptionEngine`, `AppleSpeechEngine`, `Transport`.
- Produces: `enum EngineProvider: String, CaseIterable, Sendable { case appleLocal, openAI, mistral, elevenLabs }` avec `displayName`, `secretKey: String?` (clé Keychain, nil pour apple), `config: CloudEngineConfig?`, et `func makeEngine(apiKey: String?, transport: Transport) -> TranscriptionEngine?`.

- [ ] **Step 1: Étendre le test (échoue)**

```swift
    func test_appleProvider_buildsLocalEngine_withoutKey() {
        let engine = EngineProvider.appleLocal.makeEngine(apiKey: nil, transport: MockTransport())
        XCTAssertEqual(engine?.id, "apple.local")
        XCTAssertNil(EngineProvider.appleLocal.secretKey)
    }
    func test_cloudProvider_requiresKey() {
        XCTAssertNil(EngineProvider.openAI.makeEngine(apiKey: nil, transport: MockTransport()))
        let e = EngineProvider.openAI.makeEngine(apiKey: "sk", transport: MockTransport())
        XCTAssertEqual(e?.id, CloudEngineConfig.openAI.id)
    }
```

- [ ] **Step 2: Lancer — RED**

Run: `cd FlowScribeCore && swift test --filter EngineProviderTests`
Expected: FAIL.

- [ ] **Step 3: Écrire `EngineProvider.swift`**

```swift
import Foundation

public enum EngineProvider: String, CaseIterable, Sendable {
    case appleLocal, elevenLabs, mistral, openAI

    public var displayName: String {
        switch self {
        case .appleLocal: return "Apple (local)"
        case .elevenLabs: return "ElevenLabs Scribe"
        case .mistral: return "Mistral Voxtral"
        case .openAI: return "OpenAI gpt-4o-transcribe"
        }
    }

    /// Clé sous laquelle l'API key est stockée dans le SecretStore (nil pour Apple).
    public var secretKey: String? {
        switch self {
        case .appleLocal: return nil
        case .elevenLabs: return "elevenlabs"
        case .mistral: return "mistral"
        case .openAI: return "openai"
        }
    }

    public var config: CloudEngineConfig? {
        switch self {
        case .appleLocal: return nil
        case .elevenLabs: return .elevenLabs
        case .mistral: return .mistral
        case .openAI: return .openAI
        }
    }

    /// Construit le moteur. Renvoie nil si une clé est requise mais absente.
    public func makeEngine(apiKey: String?, transport: Transport) -> TranscriptionEngine? {
        if self == .appleLocal { return AppleSpeechEngine() }
        guard let config, let apiKey, !apiKey.isEmpty else { return nil }
        return CloudTranscriptionEngine(config: config, apiKey: apiKey, transport: transport)
    }
}
```

- [ ] **Step 4: Lancer — GREEN**

Run: `cd FlowScribeCore && swift test --filter EngineProviderTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add FlowScribeCore && git commit -m "feat(m2): EngineProvider + factory" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && git push
```

---

### Task 7: `TranscriptionService` (sélection + fallback Apple)

**Files:**
- Create: `FlowScribeCore/Sources/FlowScribeCore/TranscriptionService.swift`
- Test: `FlowScribeCore/Tests/FlowScribeCoreTests/TranscriptionServiceTests.swift`

**Interfaces:**
- Consumes: `TranscriptionEngine`.
- Produces: `final class TranscriptionService` (init `primary: TranscriptionEngine, fallback: TranscriptionEngine`), `func transcribe(fileAt:locale:) async -> TranscriptionOutcome` où `enum TranscriptionOutcome: Equatable { case success(text: String, engineId: String, usedFallback: Bool) ; case failed }`.

- [ ] **Step 1: Écrire le test (échoue)**

```swift
import XCTest
@testable import FlowScribeCore

final class TranscriptionServiceTests: XCTestCase {
    struct ThrowingEngine: TranscriptionEngine {
        let id = "boom"; let capabilities = EngineCapabilities(supportsStreaming: false, supportsKeyterms: false, isLocal: false)
        func transcribeFile(at url: URL, locale: Locale) async throws -> String { throw URLError(.notConnectedToInternet) }
    }

    func test_usesPrimary_whenItSucceeds() async {
        let service = TranscriptionService(primary: MockEngine(id: "p", result: "primaire"),
                                           fallback: MockEngine(id: "apple", result: "local"))
        let out = await service.transcribe(fileAt: URL(filePath: "/tmp/x.caf"), locale: .current)
        XCTAssertEqual(out, .success(text: "primaire", engineId: "p", usedFallback: false))
    }

    func test_fallsBackToApple_whenPrimaryThrows() async {
        let service = TranscriptionService(primary: ThrowingEngine(),
                                           fallback: MockEngine(id: "apple", result: "local"))
        let out = await service.transcribe(fileAt: URL(filePath: "/tmp/x.caf"), locale: .current)
        XCTAssertEqual(out, .success(text: "local", engineId: "apple", usedFallback: true))
    }
}
```

- [ ] **Step 2: Lancer — RED**

Run: `cd FlowScribeCore && swift test --filter TranscriptionServiceTests`
Expected: FAIL.

- [ ] **Step 3: Écrire `TranscriptionService.swift`**

```swift
import Foundation

public enum TranscriptionOutcome: Equatable, Sendable {
    case success(text: String, engineId: String, usedFallback: Bool)
    case failed
}

public final class TranscriptionService: Sendable {
    private let primary: TranscriptionEngine
    private let fallback: TranscriptionEngine
    public init(primary: TranscriptionEngine, fallback: TranscriptionEngine) {
        self.primary = primary; self.fallback = fallback
    }

    public func transcribe(fileAt url: URL, locale: Locale) async -> TranscriptionOutcome {
        do {
            let text = try await primary.transcribeFile(at: url, locale: locale)
            return .success(text: text, engineId: primary.id, usedFallback: false)
        } catch {
            // Repli : on ne perd jamais l'audio, on retente en local sur le fichier.
            do {
                let text = try await fallback.transcribeFile(at: url, locale: locale)
                return .success(text: text, engineId: fallback.id, usedFallback: true)
            } catch {
                return .failed
            }
        }
    }
}
```

- [ ] **Step 4: Lancer — GREEN**

Run: `cd FlowScribeCore && swift test --filter TranscriptionServiceTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add FlowScribeCore && git commit -m "feat(m2): TranscriptionService (sélection + fallback Apple local)" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && git push
```

---

### Task 8: `CostEstimator` (pur)

**Files:**
- Create: `FlowScribeCore/Sources/FlowScribeCore/CostEstimator.swift`
- Test: `FlowScribeCore/Tests/FlowScribeCoreTests/CostEstimatorTests.swift`

**Interfaces:**
- Produces: `enum CostEstimator { static func estimateUSD(durationSeconds: TimeInterval, pricePerMinuteUSD: Double) -> Double ; static func formatted(_ usd: Double) -> String }`.

- [ ] **Step 1: Écrire le test (échoue)**

```swift
import XCTest
@testable import FlowScribeCore

final class CostEstimatorTests: XCTestCase {
    func test_estimate_scalesWithDuration() {
        XCTAssertEqual(CostEstimator.estimateUSD(durationSeconds: 120, pricePerMinuteUSD: 0.006), 0.012, accuracy: 1e-9)
        XCTAssertEqual(CostEstimator.estimateUSD(durationSeconds: 0, pricePerMinuteUSD: 0.006), 0, accuracy: 1e-9)
    }
    func test_formatted_showsFourDecimals() {
        XCTAssertEqual(CostEstimator.formatted(0.012), "$0.0120")
    }
}
```

- [ ] **Step 2: Lancer — RED**

Run: `cd FlowScribeCore && swift test --filter CostEstimatorTests`
Expected: FAIL.

- [ ] **Step 3: Écrire `CostEstimator.swift`**

```swift
import Foundation

public enum CostEstimator {
    public static func estimateUSD(durationSeconds: TimeInterval, pricePerMinuteUSD: Double) -> Double {
        max(0, durationSeconds) / 60.0 * pricePerMinuteUSD
    }
    public static func formatted(_ usd: Double) -> String {
        String(format: "$%.4f", usd)
    }
}
```

- [ ] **Step 4: Lancer — GREEN**

Run: `cd FlowScribeCore && swift test --filter CostEstimatorTests`
Expected: PASS.

- [ ] **Step 5: Commit + suite complète**

```bash
cd FlowScribeCore && swift test   # toute la suite verte
git add FlowScribeCore && git commit -m "feat(m2): CostEstimator (pur)" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && git push
```

---

### Task 9: Réglages (clés + moteur par défaut) + câblage app

**Files:**
- Create: `FlowScribe/SettingsStore.swift`
- Create: `FlowScribe/SettingsView.swift`
- Modify: `FlowScribe/FlowScribeApp.swift`

**Interfaces:**
- Consumes: `EngineProvider`, `SecretStore`/`KeychainSecretStore`, `TranscriptionService`, `URLSessionTransport`, `AppleSpeechEngine`, `DictationController` (M1).
- Produces: `@MainActor @Observable final class SettingsStore` (defaultProvider: EngineProvider persisté UserDefaults, langue) ; `SettingsView`. Câblage : le `DictationController` reçoit un `TranscriptionService(primary: moteur choisi, fallback: AppleSpeechEngine)`.

> UI + Keychain : validé par build + recette manuelle (Task 10).

- [ ] **Step 1: Écrire `FlowScribe/SettingsStore.swift`**

```swift
import SwiftUI
import FlowScribeCore

@MainActor
@Observable
final class SettingsStore {
    private let defaults = UserDefaults.standard
    private let secrets: SecretStore

    init(secrets: SecretStore) { self.secrets = secrets }

    var defaultProvider: EngineProvider {
        get { EngineProvider(rawValue: defaults.string(forKey: "defaultProvider") ?? "") ?? .appleLocal }
        set { defaults.set(newValue.rawValue, forKey: "defaultProvider") }
    }

    var localeIdentifier: String {
        get { defaults.string(forKey: "localeIdentifier") ?? "fr-FR" }
        set { defaults.set(newValue, forKey: "localeIdentifier") }
    }

    func apiKey(for provider: EngineProvider) -> String {
        guard let key = provider.secretKey else { return "" }
        return secrets.get(key) ?? ""
    }
    func setAPIKey(_ value: String, for provider: EngineProvider) {
        guard let key = provider.secretKey else { return }
        secrets.set(value.isEmpty ? nil : value, for: key)
    }
}
```

- [ ] **Step 2: Écrire `FlowScribe/SettingsView.swift`**

```swift
import SwiftUI
import FlowScribeCore

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @State private var keyDrafts: [EngineProvider: String] = [:]

    var body: some View {
        Form {
            Section("Moteur par défaut") {
                Picker("Moteur", selection: Binding(
                    get: { settings.defaultProvider },
                    set: { settings.defaultProvider = $0 })) {
                    ForEach(EngineProvider.allCases, id: \.self) { p in
                        Text(p.displayName).tag(p)
                    }
                }
            }
            Section("Clés API (stockées dans le Keychain)") {
                ForEach(EngineProvider.allCases.filter { $0.secretKey != nil }, id: \.self) { p in
                    SecureField(p.displayName, text: Binding(
                        get: { keyDrafts[p] ?? settings.apiKey(for: p) },
                        set: { keyDrafts[p] = $0 }))
                        .onSubmit { settings.setAPIKey(keyDrafts[p] ?? "", for: p) }
                }
                Button("Enregistrer les clés") {
                    for (p, v) in keyDrafts { settings.setAPIKey(v, for: p) }
                }
            }
            Section("Langue") {
                TextField("Identifiant de langue (ex. fr-FR)", text: Binding(
                    get: { settings.localeIdentifier },
                    set: { settings.localeIdentifier = $0 }))
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 360)
    }
}
```

- [ ] **Step 3: Modifier `FlowScribe/FlowScribeApp.swift`** — ajouter la fenêtre Réglages et construire le service à partir du moteur choisi.

```swift
import SwiftUI
import FlowScribeCore

@main
struct FlowScribeApp: App {
    @State private var permissions = PermissionsModel()
    @State private var settings = SettingsStore(secrets: KeychainSecretStore())
    @State private var bridge: HotkeyBridge?

    var body: some Scene {
        WindowGroup("FlowScribe") {
            VStack(spacing: 16) {
                Text("FlowScribe").font(.title2.bold())
                Text("Appuie sur ⌥Espace pour dicter.").foregroundStyle(.secondary)
                if permissions.allGranted {
                    Label("Autorisations OK", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green).font(.caption)
                } else {
                    Divider()
                    PermissionsView(model: permissions)
                }
            }
            .padding(20)
            .frame(width: 380)
            .task { await setup() }
        }
        Settings { SettingsView(settings: settings) }
        MenuBarExtra("FlowScribe", systemImage: "mic.fill") {
            Button("Quitter") { NSApplication.shared.terminate(nil) }
        }
    }

    @MainActor
    private func setup() async {
        permissions.refresh()
        await permissions.requestAll()
        guard bridge == nil else { return }
        let dir = URL.applicationSupportDirectory.appending(path: "FlowScribe/recordings")
        let transport = URLSessionTransport()
        let apple = AppleSpeechEngine()
        let provider = settings.defaultProvider
        let primary = provider.makeEngine(apiKey: settings.apiKey(for: provider), transport: transport) ?? apple
        let service = TranscriptionService(primary: primary, fallback: apple)
        let controller = DictationController(
            recorder: MicrophoneRecorder(outputDirectory: dir),
            service: service,
            output: SystemTextOutput(),
            locale: Locale(identifier: settings.localeIdentifier)
        )
        bridge = HotkeyBridge(controller: controller, hud: RecordingHUD())
    }
}
```

- [ ] **Step 4: Adapter `DictationController` (FlowScribeCore) pour consommer un `TranscriptionService`**

Le contrôleur M1 prenait un `TranscriptionEngine`. Le remplacer par un `TranscriptionService` (qui gère le fallback). Modifier `FlowScribeCore/Sources/FlowScribeCore/DictationController.swift` :
- init : `init(recorder: AudioRecorder, service: TranscriptionService, output: TextOutput, locale: Locale)`
- dans `finishRecording()` : remplacer l'appel `engine.transcribeFile` par
```swift
        let outcome = await service.transcribe(fileAt: recording.url, locale: locale)
        state = .transcribing
        switch outcome {
        case let .success(text, _, _):
            lastTranscript = text
            output.deliver(text)
        case .failed:
            lastTranscript = nil
        }
        state = .idle
```
Et adapter `DictationControllerTests` : construire un `TranscriptionService(primary: MockEngine(...), fallback: MockEngine(...))` au lieu d'un moteur direct. Lancer `swift test --filter DictationControllerTests` → vert.

- [ ] **Step 5: Build app + suite core**

Run: `cd FlowScribeCore && swift test` puis `cd .. && xcodegen generate && xcodebuild -project FlowScribe.xcodeproj -scheme FlowScribe -destination 'platform=macOS' build`
Expected: suite verte + BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add FlowScribe FlowScribeCore && git commit -m "feat(m2): réglages (clés Keychain + moteur défaut) + service avec fallback câblé" -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" && git push
```

---

### Task 10: Recette manuelle (PORTE HUMAINE)

**Files:** aucun.

- [ ] **Step 1: Suite core complète verte** — `cd FlowScribeCore && swift test`
- [ ] **Step 2: Lancer l'app**, ouvrir Réglages (⌘,), choisir un moteur cloud, coller la clé correspondante, enregistrer.
- [ ] **Step 3: Dictée** ⌥Espace dans TextEdit → le texte vient du moteur cloud choisi (qualité supérieure). Couper le Wi-Fi → re-dicter → **repli Apple local** (le texte sort quand même).
- [ ] **Step 4: Commit de clôture M2** (`git commit --allow-empty`).

---

## Auto-revue (faite à l'écriture)

- **Couverture M2** : moteurs cloud (Tasks 4-6), clés Keychain (Task 2), réseau testable (Task 1), multipart (Task 3), sélection + fallback (Task 7), coût (Task 8), réglages + câblage (Task 9), recette (Task 10). ✅
- **Hors M2 (séquencé ensuite)** : persistance/historique SwiftData + rétention, UI historique + re-transcription, glossaire auto-calibrant (M3), finitions/musique/notarisation (M4). À noter dans la spec §2 comme ré-ordonnancement, pas un retrait.
- **Placeholders** : aucun ; code réel partout. IDs de modèles/endpoints concrets (à confirmer vs docs à l'intégration — n'affecte pas les tests, qui utilisent MockTransport).
- **Cohérence des types** : `Transport.send -> (Data, HTTPURLResponse)`, `SecretStore.get/set`, `CloudEngineConfig`, `CloudTranscriptionEngine(config:apiKey:transport:)`, `EngineProvider.makeEngine`, `TranscriptionService.transcribe(fileAt:locale:) -> TranscriptionOutcome` nommés de façon cohérente entre tâches. Task 9 modifie `DictationController` (M1) pour consommer `TranscriptionService` — changement de signature documenté avec mise à jour des tests.
- **Limite assumée** : moteurs cloud non couverts par tests réseau réels (gated derrière clés) ; validés par MockTransport + recette manuelle Task 10.
```

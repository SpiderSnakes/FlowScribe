import Foundation
import FlowScribeCore

// Outil de diagnostic headless.
// Usage : flowscribe-cli <fichier-audio>
//   FLOWSCRIBE_PROVIDER = apple | openai | mistral | elevenlabs   (défaut: apple)
//   FLOWSCRIBE_KEY      = clé API (pour les moteurs cloud)
//   FLOWSCRIBE_LOCALE   = identifiant de langue (défaut: fr-FR)

func mapProvider(_ s: String) -> String {
    switch s.lowercased() {
    case "apple", "applelocal", "apple-local": return "appleLocal"
    case "openai", "gpt", "gpt-4o": return "openAI"
    case "mistral", "voxtral": return "mistral"
    case "elevenlabs", "eleven", "scribe": return "elevenLabs"
    default: return s
    }
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("""
    Usage: flowscribe-cli <fichier-audio>
      FLOWSCRIBE_PROVIDER=apple|openai|mistral|elevenlabs (défaut apple)
      FLOWSCRIBE_KEY=<clé> (pour le cloud)
      FLOWSCRIBE_LOCALE=fr-FR

    """.utf8))
    exit(2)
}

let url = URL(filePath: args[1])
let env = ProcessInfo.processInfo.environment
let providerRaw = mapProvider(env["FLOWSCRIBE_PROVIDER"] ?? "apple")
let key = env["FLOWSCRIBE_KEY"]
let locale = Locale(identifier: env["FLOWSCRIBE_LOCALE"] ?? "fr-FR")

guard let provider = EngineProvider(rawValue: providerRaw) else {
    print("Provider inconnu : \(providerRaw)"); exit(2)
}
let transport = URLSessionTransport()
guard let engine = provider.makeEngine(apiKey: key, transport: transport) else {
    print("Clé requise pour \(provider.displayName) — définis FLOWSCRIBE_KEY."); exit(2)
}

print("Moteur : \(engine.id) · langue : \(locale.identifier) · fichier : \(url.lastPathComponent)")

if let cloud = engine as? CloudTranscriptionEngine {
    let r = await cloud.validateKey()
    let status = r.status.map(String.init) ?? "-"
    print("Test clé : \(r.ok ? "✓ OK" : "✗ ÉCHEC") (HTTP \(status))\(r.message.map { " — \($0)" } ?? "")")
}

let start = Date()
do {
    let text = try await engine.transcribeFile(at: url, locale: locale)
    let elapsed = Date().timeIntervalSince(start)
    print("--- TRANSCRIPTION ---")
    print(text)
    print("---------------------")
    print(String(format: "Durée : %.1f s", elapsed))
} catch {
    print("ERREUR de transcription : \(error)")
    exit(1)
}

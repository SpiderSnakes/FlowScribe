import Foundation

/// Une correction proposée par le LLM à partir des transcriptions.
public struct CorrectionProposal: Equatable, Sendable, Identifiable {
    public var id: String { heard }
    public let heard: String        // tel que transcrit (à corriger)
    public let corrected: String    // forme correcte
    public let occurrences: Int
    public init(heard: String, corrected: String, occurrences: Int) {
        self.heard = heard; self.corrected = corrected; self.occurrences = occurrences
    }
}

/// Calibration assistée par IA : un LLM écrit lit les transcriptions et propose des règles
/// de correction (surtout noms propres / outils mal transcrits).
public enum AICalibration {
    public static let systemPrompt = """
    Tu es un correcteur de transcriptions vocales. On te donne des transcriptions (séparées par « --- »). \
    Repère les NOMS PROPRES, noms d'outils, produits, marques, commandes ou termes techniques probablement \
    MAL transcrits (ex. « Doc Ploy » au lieu de « Dokploy »). Pour chacun, propose la forme correcte. \
    Réponds UNIQUEMENT un tableau JSON, sans texte autour : \
    [{"heard":"texte tel que transcrit","corrected":"forme correcte","occurrences":nombre}]. \
    Si rien à corriger, réponds [].
    """

    /// Extrait les propositions d'une réponse LLM (tolère un texte/des fences autour du JSON).
    public static func parseProposals(from response: String) -> [CorrectionProposal] {
        guard let start = response.firstIndex(of: "["),
              let end = response.lastIndex(of: "]"), start < end else { return [] }
        let json = String(response[start...end])
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { obj in
            guard let heard = (obj["heard"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let corrected = (obj["corrected"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !heard.isEmpty, !corrected.isEmpty,
                  heard.caseInsensitiveCompare(corrected) != .orderedSame else { return nil }
            let occ = (obj["occurrences"] as? Int) ?? (obj["occurrences"] as? NSNumber)?.intValue ?? 1
            return CorrectionProposal(heard: heard, corrected: corrected, occurrences: occ)
        }
    }

    /// Analyse les transcriptions via le LLM et renvoie les propositions (vide si erreur).
    public static func propose(transcriptions: [String], provider: EngineProvider, model: String,
                               apiKey: String, transport: Transport) async -> [CorrectionProposal] {
        let joined = transcriptions.joined(separator: "\n---\n")
        let svc = TextLLMService(provider: provider, model: model, apiKey: apiKey, transport: transport)
        guard let response = try? await svc.complete(system: systemPrompt, user: joined) else { return [] }
        return parseProposals(from: response)
    }
}

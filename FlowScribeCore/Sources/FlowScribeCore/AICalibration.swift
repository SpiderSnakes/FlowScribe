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
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard let arr = extractJSONArray(from: trimmed) else {
            // Réponse non vide mais aucun tableau JSON exploitable : on le journalise pour distinguer
            // « rien à corriger » d'un échec de parsing silencieux.
            AppLog.error("AICalibration", "réponse LLM non vide mais sans tableau JSON exploitable")
            return []
        }

        let proposals: [CorrectionProposal] = arr.compactMap { obj in
            guard let heard = (obj["heard"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let corrected = (obj["corrected"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !heard.isEmpty, !corrected.isEmpty,
                  heard.caseInsensitiveCompare(corrected) != .orderedSame else { return nil }
            let occ = (obj["occurrences"] as? Int) ?? (obj["occurrences"] as? NSNumber)?.intValue ?? 1
            return CorrectionProposal(heard: heard, corrected: corrected, occurrences: occ)
        }
        return dedupe(proposals)
    }

    /// Déduplique par `heard` (insensible à la casse) : `CorrectionProposal.id == heard`, donc des doublons
    /// produiraient des ID identiques dans `ForEach` et des collisions dans le `Set` des propositions cochées.
    /// On conserve l'entrée au plus grand nombre d'occurrences (premier rencontré en cas d'égalité).
    private static func dedupe(_ proposals: [CorrectionProposal]) -> [CorrectionProposal] {
        var result: [CorrectionProposal] = []
        var indexByKey: [String: Int] = [:]
        for p in proposals {
            let key = p.heard.lowercased()
            if let i = indexByKey[key] {
                if p.occurrences > result[i].occurrences { result[i] = p }
            } else {
                indexByKey[key] = result.count
                result.append(p)
            }
        }
        return result
    }

    /// Localise le tableau JSON dans une réponse pouvant contenir de la prose et/ou des fences.
    /// 1) retire d'éventuelles fences ```json / ``` puis tente un parsing direct ;
    /// 2) à défaut, repère chaque '[' candidat et équilibre les crochets (en ignorant ceux situés dans
    ///    des chaînes JSON) jusqu'à la profondeur 0, puis teste ce sous-tableau — au lieu de prendre
    ///    aveuglément le dernier ']', qui casse dès que la prose contient un crochet.
    private static func extractJSONArray(from response: String) -> [[String: Any]]? {
        // 1) Nettoyage des fences markdown.
        var cleaned = response
        if let fenceRange = cleaned.range(of: "```") {
            // Retire la 1re fence (et un éventuel marqueur de langage « json ») puis la dernière.
            cleaned.removeSubrange(cleaned.startIndex..<fenceRange.upperBound)
            if let lang = cleaned.range(of: "json", options: [.anchored, .caseInsensitive]) {
                cleaned.removeSubrange(cleaned.startIndex..<lang.upperBound)
            }
            if let closing = cleaned.range(of: "```", options: .backwards) {
                cleaned.removeSubrange(closing.lowerBound..<cleaned.endIndex)
            }
        }
        if let arr = parseArray(cleaned) { return arr }
        if let arr = parseArray(response) { return arr }

        // 2) Équilibrage des crochets depuis chaque '[' candidat de la réponse brute.
        let chars = Array(response)
        for startPos in chars.indices where chars[startPos] == "[" {
            var depth = 0
            var inString = false
            var escaped = false
            var pos = startPos
            while pos < chars.count {
                let c = chars[pos]
                if escaped {
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == "\"" {
                    inString.toggle()
                } else if !inString {
                    if c == "[" { depth += 1 }
                    else if c == "]" {
                        depth -= 1
                        if depth == 0 {
                            let candidate = String(chars[startPos...pos])
                            if let arr = parseArray(candidate) { return arr }
                            break   // crochets équilibrés mais non parsables : on tente le '[' suivant
                        }
                    }
                }
                pos += 1
            }
        }
        return nil
    }

    private static func parseArray(_ s: String) -> [[String: Any]]? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = t.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        return arr
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

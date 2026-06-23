# R2 — Persistance & historique des transcriptions — Design

- **Date** : 2026-06-23
- **Statut** : design (validé au brainstorming v2) — en attente de relecture avant plan
- **Contexte** : 3ᵉ étape de la refonte v2. On **stocke** les transcriptions et l'**Accueil les liste** (remplace le placeholder de R1).

## 1. Vision & périmètre
Garder l'historique des dictées et le rendre exploitable depuis l'Accueil : **lister, rechercher, copier, re-transcrire (autre moteur sur l'audio sauvegardé), supprimer**, avec une **rétention** configurable.

**Dans R2 :**
- Modèle `TranscriptionRecord` persistant (texte, moteur, date, durée, chemin audio).
- `HistoryStore` (JSON + in-memory) : ajouter, lister (plus récent d'abord), supprimer, purger.
- `RetentionPolicy` (fonction pure) : déterminer les enregistrements expirés selon l'âge max.
- Enregistrement automatique à la fin d'une dictée réussie.
- Accueil : **liste réelle** (recherche, copier, supprimer, re-transcrire) à la place du placeholder.
- Réglage de **rétention** (jours ; 0 = illimité) ; purge au lancement (records + fichiers audio).

**Hors R2 :** switch rapide de modèle sur l'Accueil (R3) · Fichiers (R4) · refonte règles (R5) · motion (R6).

## 2. Modèle de données
```swift
struct TranscriptionRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let text: String          // texte final (post-corrigé / nettoyé)
    let engineId: String      // moteur ayant produit le texte
    let locale: String
    let audioFileName: String // nom du fichier CAF (dans le dossier recordings)
    let duration: TimeInterval?
}
```
- L'audio reste dans `Application Support/FlowScribe/recordings` (déjà le cas) ; on stocke le **nom** du fichier (pas le chemin absolu) pour rester robuste.

## 3. Stores & rétention
- `protocol HistoryStore: Sendable { var records: [TranscriptionRecord] { get } ; func add(_:) ; func delete(id:) ; func prune(olderThan: Date) -> [String] }` (prune renvoie les `audioFileName` supprimés, pour effacer les fichiers).
- `InMemoryHistoryStore` (tests) + `JSONHistoryStore(url:)` (prod, `Application Support/FlowScribe/history.json`). `records` triés **plus récent d'abord**.
- `enum RetentionPolicy { static func expired(_ records: [TranscriptionRecord], now: Date, maxAgeDays: Int) -> [TranscriptionRecord] }` — pur (maxAgeDays 0 = rien n'expire). **TDD.**

## 4. Enregistrement automatique
- `DictationController` gagne `var onRecord: ((TranscriptionRecord) -> Void)?`, appelé en fin de dictée **réussie** (après nettoyage) avec un record construit depuis le texte final + `engineId` de l'outcome + l'audio + la date.
- L'app branche `onRecord` → `historyStore.add` + supprime le fichier audio si la dictée a échoué (pas de record).
- Test : `onRecord` reçoit le bon texte/engineId (mock).

## 5. Accueil (liste réelle)
- `HomeView` affiche la **liste** (plus récent d'abord) : aperçu du texte, moteur, date relative, durée.
- **Recherche** (filtre texte). Par ligne : **Copier**, **Re-transcrire** (menu : choisir un moteur → relance `transcribe(fileAt: audio)` → nouveau record), **Supprimer**.
- Le gros bouton d'enregistrement + la pastille moteur restent en tête.
- Re-transcrire réutilise le pipeline (`TranscriptionService` du moteur choisi) sur l'`audioFileName` ; si l'audio a été purgé, l'action est indisponible (grisée).

## 6. Rétention
- `SettingsStore.retentionDays: Int` (UserDefaults, défaut **30** ; 0 = illimité).
- Au lancement : `RetentionPolicy.expired` → `historyStore.prune` → suppression des fichiers audio correspondants.
- Section « Rétention » dans Réglages (champ jours + « Supprimer tout l'historique »).

## 7. Architecture / composants
| Composant | Rôle | Emplacement |
|---|---|---|
| `TranscriptionRecord` | modèle persistant | FlowScribeCore |
| `RetentionPolicy.expired` | pur, testé | FlowScribeCore |
| `HistoryStore` (+ InMemory + JSON) | persistance, tri, purge | FlowScribeCore |
| `DictationController.onRecord` | hook de fin de dictée | FlowScribeCore (existant, étendu) |
| `HistoryListView` / lignes | UI Accueil | app |
| `HomeView` (modifié) | liste + recherche + actions | app |
| `SettingsView` (modifié) | réglage rétention | app |
| `FlowScribeApp` (modifié) | stores, câblage onRecord, purge au lancement, re-transcription | app |

## 8. Tests
- **TDD** : `RetentionPolicy.expired` (rien si maxAge 0, expire au-delà de l'âge, garde les récents) ; `HistoryStore` in-memory (add → tri récent d'abord, delete, prune renvoie les noms) ; `DictationController.onRecord` (texte/engineId corrects).
- **Build + recette** : Accueil (liste, recherche, copier, supprimer, re-transcrire), purge.

## 9. Risques / à vérifier
- Volume : JSON réécrit à chaque ajout — OK à l'échelle perso ; si ça devient gros, migrer SwiftData (hors R2).
- Re-transcription : l'audio doit exister (sinon action grisée) ; cohérence du `engineId` re-choisi.
- Suppression : effacer le record **et** son fichier audio.
- `Date.now`/UUID : créés dans l'app/contrôleur (process réel), pas dans un sandbox.

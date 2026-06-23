# R4 — Transcription de fichiers — Design

**Statut :** approuvé (autonomie déléguée par l'utilisateur, test global en fin de parcours)
**Date :** 2026-06-23

## Objectif

Permettre de transcrire un fichier audio existant (glisser-déposer ou sélection) avec le moteur/modèle de son choix, et verser le résultat dans l'historique — sans jamais passer par le micro.

## Pourquoi c'est peu coûteux

Le protocole `TranscriptionEngine.transcribeFile(at:locale:)` et `TranscriptionService.transcribe(fileAt:locale:)` existent déjà et sont utilisés par la dictée (qui enregistre d'abord un `.caf` puis le transcrit) et par la re-transcription. La transcription de fichiers réutilise ce chemin tel quel.

## Architecture

- **Logique pure (core, testée)** — `FileImporter.importedFileName(for:id:)` : génère un nom de fichier unique (`<uuid>.<ext>`) en conservant l'extension d'origine, pour copier le fichier importé dans le dossier `recordings` aux côtés des `.caf` de dictée.
- **Glue (couche app)** :
  - `HistoryModel.importAudio(from:id:)` : copie le fichier source dans `recordings` sous le nom unique, renvoie ce nom.
  - `FileTranscription.duration(of:)` : durée best-effort via `AVURLAsset` (nil si indéterminable).
  - `FlowScribeApp.transcribeFile(_:with:)` : importe → construit le service avec le provider choisi (repli Apple) → `transcribe(fileAt:)` → ajoute un `TranscriptionRecord` à l'historique. Renvoie `true` si succès.
- **UI** — `FilesView` (nouvelle section sidebar « Fichiers ») :
  - Zone de dépôt (`dropDestination(for: URL.self)`) + bouton « Choisir un fichier… » (`NSOpenPanel`, types audio).
  - Sélecteur provider + modèle (même Menu que l'Accueil, persiste via `settings.setModel`).
  - Bouton « Transcrire » actif quand un fichier est choisi ; état `transcribing` ; message de résultat.

## Flux de données

`FilesView` (fichier choisi + provider) → `onTranscribeFile(url, provider)` → `transcribeFile` (import + service + history.add) → l'enregistrement apparaît dans l'Accueil (même `HistoryModel` observé).

## Gestion d'erreur

- Import impossible (copie échoue) → message « Import impossible ».
- Transcription échouée (`.failed` après repli) → message « Échec — réessaie ».
- Aucune clé pour le provider cloud → `makeEngine` renvoie nil → repli Apple local automatique.

## Tests

- `FileImporterTests` : extension préservée ; pas d'extension → uuid seul ; unicité par id.
- UI/glue : vérifiées au build + test global manuel.

## Hors périmètre

- Transcription par lot de plusieurs fichiers à la fois (un fichier à la fois en v1).
- Extraction de piste audio depuis une vidéo (l'utilisateur fournit de l'audio).

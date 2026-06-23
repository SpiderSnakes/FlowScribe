# Modes (profils par usage) — Design

**Statut :** approuvé (sélection utilisateur ; réf. SuperWhisper sw-02/sw-03)
**Date :** 2026-06-24

## Objectif

Des **profils** nommés et activables qui regroupent {moteur+modèle, langue, pause musique, style de nettoyage IA}. Switcher de mode reconfigure toute la dictée en un geste. **Bonus : règle le manque de flexibilité du nettoyage IA** — chaque mode a son propre prompt de reformulation.

## Intégration à faible risque

Un mode est un **preset** : l'**activer applique ses valeurs au `SettingsStore` existant**, qui pilote déjà le pipeline via `onChange`. Le pipeline (`makeService`/`applyOptions`) reste **inchangé** — pas de rewire risqué.

## Core (testé, TDD)

- `EngineProvider` += `Codable`.
- `Mode` : `{ id, name, provider, modelId, localeIdentifier, pauseMusic, cleanupPrompt: String? }` (nil = pas de nettoyage). Codable/Identifiable/Equatable/Sendable.
- `ModeStore` (protocol) + `InMemoryModeStore` + `JSONModeStore` : `modes`, `activeModeId`, `upsert`, `delete`, `setActive`. Persistance JSON.
- `AICleanupService.cleanup(_:instruction:)` : paramètre optionnel ; nil → prompt par défaut (rétrocompatible).

## App

- `ModesModel` (@Observable) enveloppe le store (modes, activeMode, upsert/delete/setActive).
- `SettingsStore.cleanupPrompt` (UserDefaults, défaut = prompt standard) ; `makeCleanup` le passe en `instruction`.
- `applyMode(_:)` (FlowScribeApp) écrit provider/model/locale/pauseMusic/cleanup dans `SettingsStore` + `modes.setActive`.
- **Seed** : à la 1re exécution (aucun mode), créer un mode « Par défaut » depuis les réglages courants, l'activer.

## UI

- Section sidebar **« Modes »** (entre Accueil et Fichiers) : liste (nom, moteur·modèle, badge actif), **Activer**, éditer, supprimer, **+ Nouveau mode**.
- Éditeur de mode (sheet) : nom · provider Picker · modèle Picker · langue · toggle pause musique · nettoyage IA (toggle + zone de prompt éditable, défaut pré-rempli).
- Accueil : puce « Mode actif : X » avec menu de bascule rapide.

## Hors périmètre (suites)

- Activation **par app au premier plan**, **raccourci dédié par mode**, **auto-paste par mode** : différés (notés).

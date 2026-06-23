# R5 — Vocabulaire unifié — Design

**Statut :** approuvé (autonomie déléguée, test global en fin de parcours)
**Date :** 2026-06-23

## Objectif

Transformer l'onglet Vocabulaire en éditeur réel de règles de correction : règles **activables/désactivables**, de portée **globale** (tous moteurs) ou **par moteur**, **éditables** et créables manuellement — la calibration reste un moyen d'en générer automatiquement.

## Modèle de données

- `CorrectionRule` gagne `enabled: Bool` (défaut `true`). `init(from:)` custom : si la clé `enabled` est absente (JSON hérité), défaut `true` — rétrocompatibilité.
- **Portée** : clé réservée `CorrectionScope.global = "__global__"` dans le store `[String: [CorrectionRule]]` existant (aucun changement de schéma). Les autres clés restent les `engineId` runtime (`apple.local`, `openai.gpt-4o-transcribe`, `mistral.voxtral`, `elevenlabs.scribe`).

## Logique (core, testée)

- `PostCorrector.correct(_:engineId:)` fusionne `rules(for: .global)` + `rules(for: engineId)`, ne garde que `enabled`, trie par longueur de `heard` décroissante, applique.
- `CorrectionProfileStore.add` : dédoublonnage par `heard` (insensible à la casse) — une re-calibration ne réécrase pas une règle que l'utilisateur a désactivée.
- `CalibrationService.proposeRules` inchangé (produit des règles `enabled = true` par défaut).

## UI — `VocabularyView` éditeur

Une seule vue scrollable :
1. **Termes du glossaire** (existant) — biais keyterms + base de la phrase de calibration.
2. **Ajouter une règle** : champs `entendu` → `corrigé` + sélecteur de portée (Globale / un moteur) + bouton Ajouter.
3. **Règles** groupées par portée (Globale d'abord, puis chaque moteur ayant des règles) : chaque ligne = toggle `enabled`, `heard` et `replacement` éditables en place, bouton supprimer.
4. **Calibrer un moteur** (existant, en sheet) — alimente la portée du moteur calibré.

Édition via `rules(for:)` + `setRules(_:for:)` (charge → mute le tableau → réécrit) ; pas de nouvelle méthode de protocole.

## Tests

- `CorrectionRule` : décodage JSON hérité → `enabled == true`.
- `PostCorrector` : règle désactivée ignorée ; règle globale appliquée sur plusieurs moteurs ; règles existantes (casse, multi-mots) toujours vertes.
- `CorrectionProfileStore.add` : dédoublonnage par `heard`.

## Hors périmètre

- Import/export de profils de vocabulaire (plus tard).
- Règles regex avancées exposées à l'utilisateur (le remplacement reste littéral, frontières de mots).

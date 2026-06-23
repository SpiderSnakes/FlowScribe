# HUD enrichi + styles d'enregistrement — Design

**Statut :** approuvé (sélection utilisateur ; réf. SuperWhisper sw-10)
**Date :** 2026-06-24

## Objectif

Enrichir le HUD d'enregistrement à la SuperWhisper « Classic » : barre large, **waveform pleine largeur** alimentée par le vrai niveau micro, et une **ligne de raccourcis** (`Stop ⌥Espace · Annuler esc`). Offrir 3 **styles** au choix : Classic / Mini / Aucun.

## Modèle

- `RecordingWindowStyle { classic, mini, none }` (app). `SettingsStore.recordingWindowStyle` (UserDefaults, défaut `.classic`), notifie `onChange`.
- `HUDModel` : ajout d'un buffer circulaire `levels: [Double]` (capacité 64) + `pushLevel(_:)` qui met à jour `level` et fait défiler `levels`. `setLevel` du HUD appelle `pushLevel`.

## UI

- **ClassicHUDView** (~380 pt) : zone waveform (Canvas lisant `model.levels`, barres verticales arrondies miroir autour du centre, hauteur ∝ niveau, teinte `Theme.sky`) + séparateur hairline + ligne de contrôles (glyphe app à gauche ; à droite chips `Stop ⌥ Espace` et `Annuler esc`). Fond `glassTint` + `glassEffect(.clear)` + bordure hairline, coins 18.
- **Mini** = `LiveHUDView` actuel (pilule 240×56, barres d'égaliseur).
- **None** = pas de HUD live (le toast de résultat reste).

## Comportement

- `RecordingHUD.style` (mis à jour depuis `settings.onChange`). `presentLive()` :
  - `.none` → ne rien afficher.
  - `.mini` → `LiveHUDView`.
  - `.classic` → `ClassicHUDView`.
- Taille du panneau adaptée au style. Le reste (toast de résultat, positionnement bas-centre, annulation Échap) inchangé.
- Réglages → nouveau Picker « Fenêtre d'enregistrement » (Classic/Mini/Aucune).

## Hors périmètre

- Bouton « réduire » du HUD (sw-10) et transcription temps réel dans le HUD : différés.

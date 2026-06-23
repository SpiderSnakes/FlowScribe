# Onboarding des permissions — Design

**Statut :** approuvé (direction donnée par l'utilisateur + captures SuperWhisper en référence ; itératif)
**Date :** 2026-06-24
**Référence visuelle :** `docs/design-references/superwhisper-onboarding-permissions.png` (inspiration, pas copie)

## Objectif

À la première ouverture, accueillir l'utilisateur par une carte sombre en verre qui demande les autorisations une par une, avec une barre de progression qui avance — au lieu de déclencher toutes les invites système d'un coup au lancement.

## Comportement

- Affiché tant que `SettingsStore.hasSeenOnboarding == false`. Le bouton final (ou « Ignorer pour l'instant ») met `hasSeenOnboarding = true` → l'app bascule sur l'UI principale (réactif via `@Observable`).
- L'auto-`requestAll()` au lancement est **retiré** de `setup()` ; l'onboarding pilote les demandes une par une. Les utilisateurs revenants (onboarding déjà vu) gèrent les permissions via Réglages/Accueil (inchangé).

## UI — `OnboardingView`

Carte (~420 pt) centrée sur `AuroraBackground`, fond `Theme.glassTint` + `glassEffect`, bordure hairline, ombre douce.
- **Barre de progression** en haut : `grantedCount / 3` (capsule bleue animée).
- Titre « Configurons les autorisations » + sous-titre bleu « Tout reste en local — la confidentialité d'abord. »
- 3 lignes (icône + titre + description + contrôle) :
  1. **Micro** (`mic.fill`) — capter l'audio. Toujours déverrouillé.
  2. **Reconnaissance vocale** (`waveform`) — transcription Apple sur l'appareil. Verrouillée tant que micro non accordé.
  3. **Accessibilité** (`accessibility`) — coller le texte (Cmd+V). Verrouillée tant que reconnaissance vocale non accordée.
  - Accordée → coche verte ; sinon bouton « Autoriser » (désactivé si verrouillée, ligne à 45 % d'opacité).
- Si accessibilité non accordée mais étape atteinte : lien « Ouvrir les Réglages d'Accessibilité ».
- Bas : bouton proéminent « Commencer à utiliser FlowScribe » (désactivé tant que `!allGranted`) + lien discret « Ignorer pour l'instant ».
- `onReceive(NSApplication.didBecomeActiveNotification)` → `permissions.refresh()` (met à jour les coches au retour des Réglages système).

## Modèle

- `PermissionsModel` : ajout de `requestMicrophone()`, `requestSpeech()`, `requestAccessibility()` (demande + refresh) — `requestAll()` conservé pour Réglages/Accueil.
- `SettingsStore` : ajout `hasSeenOnboarding: Bool` (UserDefaults, défaut false).

## Hors périmètre

- Étapes d'onboarding au-delà des permissions (choix de moteur, clé API) — plus tard.
- Fenêtre `Window` séparée multi-scène : on reste sur un overlay dans la fenêtre principale (plus robuste).

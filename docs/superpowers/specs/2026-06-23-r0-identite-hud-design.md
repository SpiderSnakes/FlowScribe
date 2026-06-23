# R0 — Identité bleue & HUD signature — Design

- **Date** : 2026-06-23
- **Statut** : design validé en brainstorming — en attente de relecture avant plan
- **Contexte** : première étape de la refonte v2 (app à navigation latérale). R0 pose l'**identité couleur** et le **HUD « vivant »** réactif à la voix.

## 1. Vision & périmètre

Donner une **âme** à FlowScribe : une identité **bleutée** (bleu nuit → bleu ciel) et un **HUD signature** organique qui ondule au son de la voix pendant la dictée. **Aucune transcription temps réel** : le HUD est un *indicateur d'écoute*, pas du texte qui défile.

**Dans R0 :** thème couleur central (palette + accent appliqué à l'app) · flux de **niveau audio** (RMS) depuis le micro · **nouveau HUD animé** (repos / enregistrement / traitement / résultat) · indicateur de résultat conservé mais restylé.

**Hors R0 (étapes suivantes) :** sidebar/coquille de navigation (R1) · persistance/historique (R2) · fournisseurs→modèles (R3) · transcription de fichiers (R4) · vocabulaire unifié (R5) · motion design global (R6). Le **nouveau logo** sera fourni par l'utilisateur (bleu) → régénération de l'icône à ce moment ; en attendant, l'app reçoit l'accent bleu.

## 2. Thème (fondation)

- `Theme` (enum/struct dans FlowScribeCore ou l'app) exposant la palette :
  - `midnight` (bleu nuit, fonds), `sky` (bleu ciel, accent + lueur), + dégradés réutilisables (`backgroundGradient`, `glowGradient`).
- `accentColor` bleu appliqué globalement (`.tint(...)` au niveau racine).
- Couleurs définies comme constantes nommées (valeurs hex à fixer à l'implémentation), pas en dur dans les vues.
- Réutilisé par le HUD maintenant ; par la sidebar/boutons plus tard (R1+).

## 3. Niveau audio (ce qui rend le HUD vivant)

- `AudioRecorder` expose un **niveau de voix en direct** pendant l'enregistrement : un callback `onLevel: (@Sendable (Float) -> Void)?` (forme retenue), valeur **RMS normalisée 0→1**, émise depuis le tap micro (throttlé ~20–30 Hz, niveau délivré sur le main pour l'UI).
- Le calcul RMS est isolé dans une **fonction pure testable** : `AudioLevel.rms(samples: [Float]) -> Float` (racine de la moyenne des carrés, bornée 0→1). **Cible TDD.**
- Le HUD consomme ce flux pour piloter l'amplitude des ondulations.

## 4. HUD — états, visuel, motion

- **Forme/position** : capsule de verre flottante (`NSPanel` borderless, `glassEffect`), **bas-centre** ; **grandit légèrement** quand le niveau monte.
- **États** :
  - *Repos/Prêt* : point qui « respire » (pulsation lente), lueur bleue lente en fond.
  - *Enregistrement* : **anneaux concentriques / ondulations** dont l'amplitude suit le niveau RMS ; fond **dégradé bleu nuit→ciel** + **lueur qui se déplace** lentement (organique).
  - *Traitement* (après arrêt) : pulsation douce, **aucun texte**.
  - *Résultat* : bref indicateur « via \<moteur\> » / « repli Apple local » (conservé de M2) **restylé en verre bleu**, puis fondu (auto-masquage existant).
- **Techno** : SwiftUI `Canvas` + `TimelineView` (animation continue de la lueur et des ondulations) + animations ressort sur l'échelle. La lueur = dégradé radial/angulaire animé. Pas de Metal en R0 (option « aurora » par shader réservée à R6).

## 5. Architecture / composants

| Composant | Rôle | Emplacement |
|---|---|---|
| `Theme` | palette bleue + dégradés + accent (SwiftUI `Color`) | app |
| `AudioLevel.rms(samples:)` | RMS pur (testé) | FlowScribeCore |
| `AudioRecorder.onLevel` | publie le niveau live pendant l'enregistrement | FlowScribeCore |
| `HUDState` | enum repos/enregistrement/traitement | FlowScribeCore (réutilise/élargit `DictationState`) |
| `LiveHUDView` (SwiftUI) | rendu animé (ondulations + lueur + verre) | app |
| `ResultHUDView` | indicateur de résultat (restylé bleu) | app (existe, à restyler) |
| `RecordingHUD` | NSPanel hôte, expose `setLevel(_:)` + états | app (refonte du contenu) |

**Câblage** : `HotkeyBridge`/`DictationController` passent l'état au HUD (déjà le cas) ; en plus, `AudioRecorder.onLevel` → `RecordingHUD.setLevel(_:)` pendant l'enregistrement. À l'arrêt → état traitement → résultat (via `onFinish` existant).

## 6. Flux de données (dictée)
1. Déclenchement → `RecordingHUD` état *enregistrement*, `AudioRecorder` démarre.
2. Chaque buffer micro → `AudioLevel.rms` → `onLevel` → `RecordingHUD.setLevel` → ondulations.
3. Arrêt → état *traitement* (pulsation) pendant la transcription.
4. `onFinish(outcome)` → *résultat* (« via \<moteur\> ») bref → fondu.

## 7. Tests
- **Unitaire (TDD)** : `AudioLevel.rms` (silence→0, signal plein→~1, monotone avec l'amplitude, robustesse tableau vide).
- **Build + œil** : rendu HUD, animations, NSPanel, intégration du niveau réel (recette manuelle).

## 8. Risques / à vérifier
- Perf de l'animation continue (`TimelineView`/`Canvas`) : viser 60 fps, throttler le niveau.
- Cohérence du niveau RMS selon le format du tap (mono/float) → normalisation.
- Le HUD ne doit pas voler le focus (NSPanel non-activating, déjà en place).
- Couleurs exactes (hex) à fixer à l'implémentation ; logo bleu fourni ultérieurement.

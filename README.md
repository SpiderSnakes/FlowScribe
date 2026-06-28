# FlowScribe

**Dictée vocale native pour macOS — gratuite, locale d'abord, avec tes propres clés.**

FlowScribe transcrit ta voix en texte et le colle là où se trouve ton curseur, via un simple
raccourci clavier. Par défaut tout se passe **en local** (modèle de transcription on-device d'Apple) ;
tu peux brancher tes propres clés API (OpenAI, Mistral, ElevenLabs, Anthropic, Google) pour la
transcription cloud et/ou la reformulation écrite. Aucune donnée n'est envoyée nulle part tant que
tu n'as pas configuré de clé.

> Apple Silicon · macOS 26+ · SwiftUI + AppKit natif.

---

## Fonctionnalités

- **Dictée au raccourci** (⌥Espace par défaut) : appui maintenu (push-to-talk) ou appui simple
  (bascule). Le texte est collé dans l'app active **et** copié dans le presse-papier.
- **Fenêtre d'enregistrement** flottante et **déplaçable** (styles Classic / Mini / Aucune), avec une
  waveform organique en temps réel.
- **Modes** : des profils par tâche (fournisseur de transcription, modèle, langue, pause musique,
  reformulation écrite optionnelle).
- **Oral / Écrit séparés** : choisis un fournisseur pour la transcription (oral) et un autre pour la
  reformulation/calibration (écrit).
- **Corrections** : règles globales « entendu → corrigé » + glossaire de tes termes techniques.
- **Calibration par IA** : un modèle écrit lit tes transcriptions et propose des règles (surtout les
  noms propres mal transcrits) ; tu valides celles à garder.
- **Historique** : relire, réécouter l'audio, **re-transcrire** avec un modèle précis, copier, créer
  une règle, **révéler le fichier dans le Finder**, rétention configurable. Les transcriptions qui
  échouent sont **conservées** (audio gardé) pour être relancées.
- **Enregistrement à toute épreuve** : l'audio est capturé dans un conteneur CAF (robuste à un crash),
  puis converti en WAV **uniquement après vérification** — l'original n'est supprimé que si le WAV est
  valide. Au lancement, tout enregistrement laissé orphelin par une fermeture inattendue est **récupéré**
  dans l'historique pour relance. Aucune perte d'audio.
- **Mode arrière-plan « invisible »** (façon SuperWhisper) : sans icône Dock ni barre des menus,
  démarrage masqué, l'app reste lancée fenêtre fermée ; on rouvre les réglages en relançant via
  Spotlight. La dictée reste pilotée par le raccourci.
- **Thème « Voix → Lumière »** : palettes et intensité d'effets réglables (Réglages → Apparence),
  qui respectent « Réduire les animations » du système.
- **Diagnostics** : un fichier de journaux (Réglages → Diagnostics) à transmettre en cas de souci.

## Confidentialité

- L'**audio** est enregistré localement dans `~/Library/Application Support/FlowScribe/recordings`.
- Les **clés API** sont stockées **uniquement dans le Trousseau macOS** (jamais dans les préférences,
  jamais journalisées).
- Le **modèle Apple** transcrit **sur l'appareil**, hors ligne. Les fournisseurs cloud ne sont
  appelés que si tu as saisi une clé pour eux.
- Le **fichier de journaux** est volontairement détaillé pour faciliter le diagnostic, mais ne contient
  que des **métadonnées** (moteur, modèle, durée, tailles de fichier, statut HTTP, nom d'hôte, erreurs)
  — **jamais de clé API ni de texte de transcription**.

## Installation (DMG)

1. Télécharge `FlowScribe-0.2.dmg` depuis la page [Releases](../../releases).
2. Ouvre le DMG, glisse **FlowScribe** dans **Applications**, lance-le.
   L'app est **signée Developer ID et notarisée par Apple** → elle s'ouvre directement, **sans
   avertissement Gatekeeper**.
3. Accorde les autorisations demandées (**Micro**, **Reconnaissance vocale**, **Accessibilité** pour
   le collage). Tu peux les régler plus tard dans Réglages.

## Compiler depuis les sources

Prérequis : **Xcode 27**, **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** (`brew install xcodegen`).
Le `.xcodeproj` est généré (non versionné).

```bash
xcodegen generate
xcodebuild -project FlowScribe.xcodeproj -scheme FlowScribe -configuration Debug \
  -derivedDataPath build build
open build/Build/Products/Debug/FlowScribe.app
```

Tests du cœur (logique pure, sans UI) :

```bash
swift test --package-path FlowScribeCore
```

## Fournisseurs & clés

| Fournisseur | Oral (transcription) | Écrit (reformulation / calibration) |
|---|:---:|:---:|
| **Apple (local)** | ✅ (sur l'appareil, sans clé) | — |
| **ElevenLabs** | ✅ | — |
| **Mistral** | ✅ | ✅ |
| **OpenAI** | ✅ | ✅ |
| **Anthropic** | — | ✅ |
| **Google** | — | ✅ |

Ajoute tes clés dans **Réglages → Clés API** (stockées dans le Trousseau).

## Architecture

- **`FlowScribeCore/`** — package Swift testable, sans UI : pipeline de transcription, moteurs,
  stores JSON, corrections, modes, services LLM, journalisation. ~100 tests XCTest.
- **`FlowScribe/`** — l'app SwiftUI + AppKit : HUD, fenêtre principale, réglages, onboarding, thème.
- Seule dépendance tierce : **[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts)**
  (raccourci global). Tout le reste = frameworks système.

---

*Projet personnel — développé sur macOS, Apple Silicon.*

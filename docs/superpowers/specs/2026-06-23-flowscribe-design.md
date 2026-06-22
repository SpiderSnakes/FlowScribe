# FlowScribe — Design v1

- **Date** : 2026-06-23
- **Plateforme** : macOS natif, Apple Silicon, cible **macOS 26+** (requis pour `SpeechTranscriber`)
- **Statut** : design validé — passage au plan d'implémentation

---

## 1. Vision & principes

FlowScribe est un outil de **dictée vocale** macOS, **gratuit et BYO-key** (tu fournis tes propres clés API, tu paies ton usage, pas d'abonnement). Il vise à remplacer les apps payantes et frustrantes (SuperWhisper, dictée web ChatGPT) en corrigeant leurs deux pires défauts : **perdre un enregistrement** quand ça plante, et **devoir corriger le texte à la main** à chaque fois.

Trois principes non négociables :

1. **Jamais perdre l'audio.** Tout est enregistré sur disque *avant et pendant* la transcription. Une coupure réseau ou un crash ne coûte qu'un re-essai, jamais la dictée.
2. **Moteurs interchangeables.** « Enregistrer » et « transcrire » sont deux briques découplées qui communiquent par un fichier audio + une interface commune. Changer de moteur ou re-transcrire est trivial.
3. **Qualité d'abord (zéro correction).** On privilégie la fidélité du résultat sur le temps réel. Le glossaire auto-calibrant et le choix du meilleur moteur FR servent l'objectif « ne plus jamais repasser corriger à la main ».

---

## 2. Périmètre

### Dans la v1
- Enregistrement systématique sur disque + cache + **re-transcription** depuis le fichier.
- **4 moteurs** : Apple local (défaut zéro-config) · ElevenLabs Scribe v2 (défaut premium dès clé) · Mistral Voxtral Transcribe 2 · OpenAI gpt-4o-transcribe (fallback).
- **Live preview adaptatif** : moteur streaming → texte live ; moteur batch → fenêtre « enregistrement » + contrôles.
- **Glossaire auto-calibrant (intégralité en v1)** : glossaire manuel + keyterms + **post-correction déterministe par moteur** + **calibration par lecture** (diff déterministe → règles proposées, validées par l'utilisateur) + **passe IA de proposition de corrections** (toggle in-app, off par défaut pour coût/vie privée) + **import de doc → extraction de termes**. Tout est livré en v1.
- **Hotkey global** (Option+Espace par défaut, customisable) : tap = bascule, maintien = push-to-talk.
- **Présence Dock + barre de menus.**
- **Sortie** : collage au curseur + presse-papier + historique.
- **Contrôle musique** : cascade précise (AppleScript Music/Spotify) → touche média universelle ; ne relance que ce qui a été mis en pause.
- **Nettoyage IA optionnel** (off par défaut).
- **Rétention configurable** (défaut 7 jours, jusqu'à « jamais » ; épinglage ; « supprimer maintenant »).
- **Auto-détection FR/EN** (forçable par profil).
- **Audio** : archive haute qualité (48 kHz lossless) + downsample 16 kHz par moteur ; **sélecteur de périphérique d'entrée** ; récupération après crash.
- **BYO-key** (Keychain) + **estimateur de coût** par dictée.
- **Distribution** : DMG notarisé (hors App Store).

### Différé (v1.5+)
- Moteurs **locaux** Whisper / Voxtral / Parakeet (téléchargement de modèles).
- Moteur AssemblyAI Universal-3 Pro.
- **Profils de reformatage** (email, notes, commentaire de code, prompt).
- Diarisation (« qui parle »).
- Streaming cloud comme mode live par défaut.
- Synchronisation iCloud / multi-appareils.

---

## 3. Stack technique

- **Swift + SwiftUI**, AppKit là où nécessaire (panel flottant, item barre de menus).
- **AVAudioEngine** pour la capture (tap sur l'input node → écriture fichier + émission de buffers).
- **`SpeechAnalyzer` / `SpeechTranscriber`** (framework `Speech`, macOS 26+) pour le moteur Apple local (streaming, résultats volatils + finalisés).
- **`KeyboardShortcuts`** (Sindre Sorhus, MIT) pour le hotkey global customisable (handlers keyDown/keyUp → distinction tap/maintien).
- **SwiftData** pour l'historique et les profils ; **Keychain** pour les clés API.
- Réseau via `URLSession` (REST batch + WebSocket pour le streaming cloud).
- **Distribution** : app signée Developer ID, **notarisée**, livrée en DMG.

---

## 4. Décisions de conception (et leur justification)

### 4.1 Moteurs & défaut
Comparatif multi-agents (juin 2026, vérifié contre benchmarks indépendants — pas le marketing vendeur) :

| Moteur | Français | Vocab custom | Live | Local | Prix indicatif |
|---|---|---|---|---|---|
| **ElevenLabs Scribe v2** | #1 indépendant (ServiceNow code-switching, 06/2026) | Keyterms FR ✅ | ✅ <150 ms | ❌ | ~0,22 $/h batch · ~0,39 $/h live |
| **Mistral Voxtral Transcribe 2** | Très bon (1 cran sous Scribe ; ~6 % CV-FR) | Biasing EN-first, FR expérimental ⚠️ | ✅ <200 ms | ✅ open weights | ~0,003–0,006 $/min |
| **OpenAI gpt-4o-transcribe** | Le plus faible du trio (+ risque de dérive de langue) | Prompt mou ⚠️ | ✅ (gpt-realtime-whisper) | ❌ | ~0,006 $/min |
| **Apple SpeechTranscriber** | Bon en lecture propre, se dégrade sur jargon/accents | ❌ (post-correction maison) | ✅ natif | ✅✅ | Gratuit |

- **Défaut zéro-config (sans clé)** : Apple SpeechTranscriber — gratuit, instantané, privé, natif, fonctionne dès le 1er lancement.
- **Défaut recommandé dès qu'une clé est ajoutée** : ElevenLabs Scribe v2.
- **Honnêteté** : afficher le coût par dictée au tarif *réel* (Scribe live ≈ 0,39 $/h, pas le tarif batch). gpt-4o gardé comme fallback familier, pas comme défaut FR.

### 4.2 Live preview adaptatif
Piloté par la capacité `supportsStreaming` du moteur sélectionné : `true` → la fenêtre flottante affiche le flux volatil ; `false` → elle affiche onde + « enregistrement… » + contrôles, le transcript arrive à l'arrêt. **Qualité > temps réel.**

### 4.3 Déclenchement
Hotkey global (Option+Espace par défaut, customisable) — **tap = bascule** (idéal longues dictées), **maintien = push-to-talk** (bursts courts).

### 4.4 Présence
**Dock + barre de menus** : icône Dock + fenêtre principale, plus un item barre de menus (statut + bascule rapide).

### 4.5 Contrôle musique
Interface `MediaController` avec **cascade de stratégies** : AppleScript précis pour Music.app & Spotify (lit `player state`, ne relance que ce qui jouait) → repli touche média universelle (navigateur, podcasts). Un flag d'état garantit qu'**on ne relance que ce qu'on a soi-même mis en pause**. Activable/désactivable.
> ⚠️ Le framework privé `MediaRemote` est verrouillé depuis macOS 15.4 (entitlement non accordé aux tiers) → on ne s'appuie **pas** dessus. La cascade ci-dessus n'utilise aucune API privée.

### 4.6 Nettoyage IA
Optionnel, **off par défaut**. Transcription brute par défaut (fidèle, gratuit). Un bouton/toggle « nettoyer » passe le texte dans Mistral/GPT (clé existante) : ponctuation, retrait des « euh », reformatage léger.

### 4.7 Rétention
**N jours puis auto-suppression**, configurable (jours / semaines / mois / jamais), épinglage des enregistrements à garder, action « supprimer maintenant ». Défaut : 7 jours.

### 4.8 Langue & distribution
Auto-détection FR/EN (forçable par profil). DMG notarisé hors App Store (Accessibilité, hotkey global, contrôle musique et BYO-key incompatibles avec le sandbox App Store).

---

## 5. Architecture modulaire

Chaque module a une responsabilité unique et se teste isolément.

| Module | Rôle | Dépend de |
|---|---|---|
| `AudioRecorder` | Capture micro → fichier disque (archive HQ) + flux de buffers downsamplés. Sélection du périphérique d'entrée. Écriture incrémentale + récupération crash. | AVAudioEngine |
| `TranscriptionEngine` (protocole) | `transcribeStreaming(buffers) -> AsyncStream<TranscriptChunk>` · `transcribeFile(url) -> Transcript` · `capabilities` (`supportsStreaming`, `supportsKeyterms`, `isLocal`) · langues · `estimateCost`. | — |
| `AppleSpeechEngine` | Implémentation `SpeechTranscriber` (streaming local). | Speech |
| `ElevenLabsEngine` / `VoxtralEngine` / `OpenAIEngine` | Implémentations cloud (batch REST + WebSocket pour celles qui streament). | URLSession, KeychainStore |
| `TranscriptionService` | Choisit le moteur, orchestre live→final, applique post-correction + nettoyage, gère le **fallback** (réseau KO → finalise le fichier via Apple local). | EngineRegistry, VocabularyService |
| `GlossaryStore` | Termes du glossaire ; import de doc + extraction de candidats. | SwiftData |
| `CalibrationService` | Session de calibration : lecture → transcription moteur → alignement/diff → règles proposées (+ passe IA optionnelle). | Aligner, engines, PostProcessor |
| `Aligner` | **Fonction pure** d'alignement de séquences (référence vs hypothèse) → substitutions candidates. | — |
| `CorrectionProfileStore` | Règles `entendu→correct` **par moteur** (source : calibration / manuel / IA). | SwiftData |
| `PostCorrector` | Applique le profil du moteur actif (remplacement flou déterministe) après transcription. | CorrectionProfileStore |
| `PostProcessor` | Nettoyage IA optionnel (chat Mistral/GPT). | URLSession, KeychainStore |
| `MediaController` | Cascade pause/reprise musique + flag d'état. | AppleScript bridge |
| `OutputManager` | Collage au curseur (CGEvent Cmd+V) + presse-papier + remise à l'historique. | Accessibilité |
| `HistoryStore` | Persiste audio + transcript + moteur + coût ; rétention ; épinglage ; re-transcription. | SwiftData |
| `HotkeyManager` | Hotkey global, détection tap vs maintien. | KeyboardShortcuts |
| `KeychainStore` | Clés API par fournisseur. | Keychain |
| `CostEstimator` | Estimation de coût par dictée pour les moteurs cloud. | — |
| `PermissionsCoordinator` | Micro, reconnaissance vocale, Accessibilité, Input Monitoring ; onboarding. | — |

**Le pivot est `TranscriptionEngine`** : il rend les moteurs interchangeables, pilote l'UI (via `supportsStreaming`) et rend fallback + re-transcription triviaux.

---

## 6. Sous-système Glossaire & Calibration (différenciateur)

Objectif : **« zéro correction »** sans saisie manuelle terme par terme.

### 6.1 Glossaire à deux étages (runtime)
- **Keyterms** : la liste de termes est injectée aux moteurs qui le supportent (Scribe, plus tard AssemblyAI/Deepgram) pour biaiser la reconnaissance *en amont*.
- **Post-correction** : `PostCorrector` applique, *en aval*, le `CorrectionProfile` du moteur actif (remplacement flou déterministe) — fonctionne même pour les moteurs sans biasing (Apple, gpt-4o).

### 6.2 Calibration par lecture (apprentissage)
1. L'app présente un **texte de référence** (généré à partir du glossaire — phrases naturelles, contextuelles — ou importé), termes cibles surlignés.
2. L'utilisateur lit → enregistré → transcrit par **le moteur en cours de calibration**.
3. `Aligner` aligne hypothèse vs référence → repère les substitutions là où un terme cible attendu diffère (`Dokploy` ↔ `doc ploy`).
4. **Règles proposées** `entendu → correct`, **propres au moteur**. Passe **IA optionnelle** (clé) : généralise les variantes, avec règles spécifiques au modèle.
5. **Validation humaine** : l'utilisateur accepte/édite/rejette → enregistrées dans le `CorrectionProfile` du moteur.

### 6.3 Import & extraction
Coller/importer un document → extraction de candidats (mots capitalisés, tokens « code-ish », hors-dictionnaire ; option IA) → proposition d'ajout au glossaire → alimente les textes de calibration.

### 6.4 Principes
- **Par moteur** : chaque moteur se trompe différemment ; les règles sont liées à `engineId`.
- **Déterministe d'abord, IA en option** : l'alignement (certain, gratuit, hors-ligne) est le socle ; l'IA (supposé) est une couche désactivable. Jamais mélangés.
- **Humain dans la boucle** : aucune règle auto-appliquée sans validation, pour ne pas corrompre les transcriptions futures.

---

## 7. Audio : capture, qualité, format, crash, périphérique

- **Capture** : `AVAudioEngine`, tap sur l'input node. **Sélecteur de périphérique d'entrée** dans les réglages.
- **Double sortie** : archive **haute qualité lossless** (≈48 kHz) pour la fidélité et la re-transcription future + **downsample 16 kHz mono** à la volée pour chaque moteur (format ASR optimal, upload léger).
- **Format disque** : **CAF** (Core Audio Format), pensé pour la capture live et **robuste au crash** (pas de finalisation d'en-tête nécessaire). Export WAV/FLAC/mp3 selon ce qu'attend chaque moteur.
- **Écriture incrémentale** : le PCM est écrit au fil de l'eau pendant la parole.
- **Récupération crash** : au lancement, FlowScribe détecte les enregistrements orphelins (session interrompue) et propose de les transcrire. Zéro perte.

---

## 8. Flux d'une dictée

1. Hotkey → start (tap = bascule / maintien = push-to-talk).
2. `MediaController` met la musique en pause (si elle jouait & activé) et mémorise.
3. `AudioRecorder` démarre → écrit le fichier CAF + émet les buffers.
4. **Fenêtre flottante** : moteur streaming → texte live volatil ; moteur batch → onde + « enregistrement… » + Stop/Annuler.
5. Stop → fichier finalisé.
6. `TranscriptionService` finalise : streaming → résultat du flux ; batch → `transcribeFile(url)`. **Réseau KO → fallback Apple local sur le fichier sauvegardé.**
7. `PostCorrector` (profil du moteur) → (option) `PostProcessor` (nettoyage IA).
8. `OutputManager` : collage au curseur + presse-papier.
9. `HistoryStore` : sauvegarde (audio, transcript, moteur, coût estimé).
10. `MediaController` relance exactement ce qu'il avait mis en pause.

---

## 9. Surfaces UI

- **Fenêtre flottante (HUD)** : panel borderless flottant ; onde + statut ; transcript live si streaming ; boutons Stop/Annuler ; position configurable.
- **Fenêtre principale (Dock)** :
  - **Historique** : liste (recherche, lecture audio, **re-transcrire avec sélecteur de moteur**, copier, épingler).
  - **Réglages** : moteur + défaut · clés API · hotkey · langue · **périphérique d'entrée** · **glossaire + calibration + import** · musique (on/off) · nettoyage IA (on/off + modèle cible) · **rétention** (durée + supprimer maintenant) · qualité audio · lancement au démarrage · position du HUD.
  - **Onboarding** : permissions guidées + saisie de clé.
- **Item barre de menus** : statut + bascule rapide + ouvrir la fenêtre.

---

## 10. Permissions

Micro · Reconnaissance vocale (Speech) · Accessibilité (collage au curseur) · Input Monitoring (hotkey global). Onboarding guidé par `PermissionsCoordinator`, avec dégradation propre si une permission manque.

---

## 11. Résilience & erreurs

- Réseau/cloud KO → finalisation depuis le fichier (fallback Apple local), audio jamais perdu.
- Erreur moteur → message dans le HUD + **re-essayer avec un autre moteur** en un clic.
- Crash pendant l'enregistrement → récupération du fichier orphelin au lancement.
- Clé manquante/invalide → retombe sur Apple local + invite à configurer.

---

## 12. Coût & transparence

`CostEstimator` affiche une estimation par dictée pour les moteurs cloud, au **tarif réel** du mode utilisé (batch vs realtime). Objectif : pas de mauvaise surprise BYO-key.

---

## 13. Modèle de données (esquisse)

- `Recording` : id, url fichier CAF, date, durée, périphérique, statut, épinglé.
- `Transcript` : id, recordingId, engineId, texte brut, texte corrigé, langue, coût estimé, date.
- `GlossaryTerm` : id, terme, variantes, source.
- `CorrectionRule` : id, engineId, motif (entendu), remplacement, confiance, source (calibration/manuel/IA).
- `Settings` : moteur défaut, hotkey, langue, périphérique, rétention, toggles musique/nettoyage, qualité audio, position HUD.

---

## 14. Stratégie de test

- **Unitaire (cœur logique, sans réseau ni audio réel)** :
  - `Aligner` (alignement de séquences) — fonction pure, **cible TDD prioritaire**.
  - `PostCorrector` (remplacement flou) — exactitude des corrections.
  - Machine à états `MediaController` (ne relance que ce qu'on a pausé).
  - Sélection / fallback de moteur dans `TranscriptionService`.
  - Nettoyage de rétention de `HistoryStore`.
  - `CostEstimator`.
  - Détection tap vs maintien de `HotkeyManager`.
  - Récupération de fichier orphelin.
- **Adaptateurs moteurs** : conformité au protocole avec audio mocké ; smoke tests live gated derrière les clés (optionnels).
- **Manuel / intégration fine** : UI, capture audio réelle, collage au curseur, sessions de calibration.

---

## 15. Risques & points à vérifier à l'implémentation

- **IDs/endpoints exacts des modèles** (ils évoluent) : Apple `SpeechTranscriber` (API macOS 26) ; ElevenLabs Scribe v2 (STT batch + WebSocket realtime + keyterms) ; Mistral Voxtral Transcribe 2 (`/v1/audio/transcriptions` + endpoint realtime) ; OpenAI `gpt-4o-transcribe` (`/v1/audio/transcriptions`). À confirmer via docs officielles au moment de coder.
- **Contrôle musique** : valider la cascade AppleScript + touche média sur macOS 27 ; `MediaRemote` privé exclu (entitlement non accordé).
- **Tarif Scribe realtime** ≈ 0,39 $/h (≠ batch) — refléter dans `CostEstimator`.
- **Collage au curseur** : Cmd+V via CGEvent (compatible partout) vs insertion AX — choisir à l'implémentation.
- **`SpeechTranscriber`** : gestion du téléchargement/présence du modèle de langue au premier usage.

---

## 16. Questions ouvertes / différées

- Génération automatique des textes de calibration : règles de composition des phrases (densité de termes, longueur) — à affiner.
- Extraction de termes à l'import : heuristique seule vs IA — démarrer heuristique, IA en option.
- Profils de reformatage (email/notes/code) : différés v1.5.

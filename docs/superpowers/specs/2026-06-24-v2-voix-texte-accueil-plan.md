# FlowScribe v2 — Séparation voix/texte, refonte clés API, Modes, Accueil & calibration IA

**Statut :** PLAN proposé — à valider par l'utilisateur avant implémentation.
**Date :** 2026-06-24
**Réfs visuelles :** `docs/design-references/superwhisper/` (BYO keys, model picker, mode detail).

## 0. Clarification — le « nettoyage IA »

Aujourd'hui : le texte transcrit est **envoyé à un LLM cloud via la clé de l'utilisateur** (`AICleanupService` → Mistral `mistral-small-latest`, sinon OpenAI `gpt-4o-mini`), avec un prompt système. C'est donc une **vraie 2ᵉ passe d'IA écrite**, pas un traitement local. La refonte rend le **modèle écrit choisi explicitement** (provider + modèle).

## 1. Fondation — modèle de fournisseurs à capacités (oral / écrit)

Aujourd'hui `EngineProvider` confond fournisseur + transcription. On le remplace par :

- `Provider` : `apple, openAI, mistral, elevenLabs, anthropic, google`
  - `displayName` (nom seul : « OpenAI », « ElevenLabs », « Mistral »…)
  - `secretKey` (compte Keychain ; nil pour Apple)
  - `capabilities: Set<Capability>` avec `Capability = .transcription (oral) | .text (écrit)`
  - `transcriptionModels: [EngineModel]` et `textModels: [EngineModel]`
- Répartition :
  - **Apple** — oral seul, sans clé (`apple`, sur l'appareil).
  - **OpenAI** — oral (`gpt-4o-transcribe`, `gpt-4o-mini-transcribe`, `whisper-1`) + écrit (`gpt-4o`, `gpt-4o-mini`, + 5.x quand dispo).
  - **Mistral** — oral (`voxtral-mini-latest`) + écrit (`mistral-small-latest`, `mistral-large-latest`).
  - **ElevenLabs** — oral seul (`scribe_v2`). *(Pas de modèle écrit.)*
  - **Anthropic** — écrit seul (Claude).
  - **Google** — écrit seul (Gemini).
- Une **clé par fournisseur** couvre toutes ses capacités (la clé OpenAI sert oral ET écrit).
- Côté Core : `CloudTranscriptionEngine` (existant) pour l'oral ; généraliser `AICleanupService` en **`TextLLMService`** (chat completions) avec configs OpenAI/Mistral/Anthropic/Google, utilisé pour la reformulation ET la calibration IA.

## 2. Refonte de la carte « Clés API » (Réglages)

- Liste des fournisseurs **par nom** (tous sauf Apple), chacun avec **badges de capacité** : 🎙️ Oral / ✍️ Écrit.
- Par fournisseur : champ **clé épuré** (pas de gros bloc), bouton **Tester** + **Enregistrer**, statut discret.
- Regroupement visuel clair **Oral** vs **Écrit** (un fournisseur mixte apparaît dans les deux, ou avec deux badges — à trancher au design ; recommandation : une ligne par fournisseur + badges).
- Test adapté à la capacité : oral → endpoint transcription ; écrit → ping chat.

## 3. Modes — provider + modèle séparés, et reformulation écrite

L'éditeur de mode devient :
- **Transcription** : `Picker Fournisseur` (nom seul) → `Picker Modèle` (modèles oral du fournisseur). Langue (déjà en menu).
- **Reformulation (2ᵉ passe, optionnelle)** : toggle + `Picker Fournisseur écrit` → `Picker Modèle écrit` + zone de **prompt** (style mail / notes / code…). Remplace l'actuel « nettoyage IA ».
- `Mode` (Core) migre : `{ transcriptionProvider, transcriptionModelId, localeIdentifier, pauseMusic, reformulation: { enabled, provider, modelId, prompt }? }`. Décodage rétrocompatible des anciens modes (provider→transcription, cleanupPrompt→reformulation).
- Affichage des modes : nom du fournisseur seul (« ElevenLabs », pas « Scribe v2 »).

## 4. Règles de correction → globales uniquement (pour l'instant)

- Suppression de la portée par moteur dans l'éditeur : **toutes les règles sont globales**.
- `RulesEditorView` : liste plate (entendu → corrigé, activable). Plus de sélecteur de portée.
- `PostCorrector` applique les règles globales (la portée par moteur reste dans le store mais inutilisée — réactivable en V2).

## 5. Calibration assistée par IA (remplace/complète la calibration vocale)

- Choisir un **modèle écrit** (provider + modèle) + le **moteur de transcription** dont on analyse les transcriptions (ou « toutes »).
- Le LLM lit les transcriptions (en lot, ou une seule depuis le détail), repère les erreurs récurrentes — surtout **noms propres / outils** (ex. « DocPloy » → « Dokploy ») — et renvoie des **propositions structurées** `entendu → corrigé` (avec occurrences + confiance).
- **Fenêtre de revue** : cocher les propositions à accepter → création de **règles globales**.
- Deux entrées : (a) menu **Calibration** (lot) ; (b) **depuis une transcription** (détail / sélection de texte).
- La calibration vocale actuelle (lecture d'une phrase) est conservée comme option secondaire, ou retirée — recommandation : la garder en repli mais mettre l'IA en avant.

## 6. Accueil & vue détail d'une transcription

- **Refonte Accueil** : cartes de **sessions** lisibles (texte tronqué, **date/heure au format système 24 h** — correction du bug d'affichage), moteur, durée. Libellés plus clairs.
- **Clic sur une session → vue détail plein écran** :
  - **Écouter** l'enregistrement (`AVAudioPlayer` sur le `.caf`).
  - **Re-transcrire** (choix du moteur).
  - **Copier**.
  - **Sélection de texte → créer une règle de correction** (sélection = « entendu », saisie du « corrigé ») ; + clic droit « Créer une règle » / « Proposer des corrections (IA) ».
  - **Supprimer** la session.
  - Bonus : coût estimé (`CostEstimator`), nombre de mots, moteur, langue.

## 7. Réglages — supprimer tous les enregistrements

- Bouton **« Supprimer tous les enregistrements »** au-dessus de la section Conservation (avec confirmation), purge historique + fichiers audio.

## Plan d'implémentation (par phases, chacune buildable + mergée)

1. **Fondation moteurs** (Core, TDD) : `Provider` + `Capability` + modèles oral/écrit ; `TextLLMService` ; configs Anthropic/Google. Adapter `makeService`/cleanup.
2. **Carte Clés API** (Réglages) : fournisseurs par nom + badges oral/écrit + champ épuré + test/save.
3. **Modes** : split provider/modèle + section reformulation écrite ; migration `Mode`.
4. **Règles globales** : simplification éditeur + portée.
5. **Accueil + vue détail** : cartes sessions, date 24 h, détail (lecture audio, re-transcrire, copier, sélection→règle, supprimer) ; bouton supprimer-tout.
6. **Calibration IA** : `TextLLMService` → propositions de règles → fenêtre de revue (lot + depuis détail).

Ordre recommandé : 1 → 2 → 3 → 4 → 5 → 6. Les phases 4 et 7 (supprimer-tout) sont petites et peuvent s'intercaler.

## Mes idées / avis en plus

- **Filtrage des pickers par capacité** : ne proposer que des modèles oral là où on transcrit, écrit là où on reformule — évite les erreurs.
- **Vue détail = cœur du produit** : y centraliser coût estimé + durée + nb mots ; c'est là que la sélection→règle et la calibration IA prennent tout leur sens.
- **Calibration IA** : dédoublonner les propositions, afficher le **nombre d'occurrences** et un **score de confiance**, bouton « Tout accepter », et possibilité d'éditer la correction avant d'accepter.
- **Modes** : étiqueter clairement « brut » vs « reformulé » dans la liste ; langue « Auto » (Apple sait détecter).
- **Test des fournisseurs écrits** : un vrai ping chat (jeton minime) pour valider la clé écrite.
- **Différé/V2 (noté)** : activation de mode par app au premier plan, raccourci par mode, transcription en direct, règles par moteur réactivées.
- **Dette technique signalée par l'audit, encore ouverte** : AppleScript pause-musique hors-thread principal, écriture audio hors thread temps réel — à traiter dans une passe stabilité dédiée.

## Questions ouvertes (avant implémentation)

1. Liste des fournisseurs écrit : **OpenAI, Mistral, Anthropic, Google** — OK ? (d'autres ?)
2. Migration des modes existants : **migrer** (recommandé, transparent) vs **réinitialiser** un mode par défaut neuf ?
3. Calibration vocale (lecture de phrase) : **garder en repli** ou **retirer** au profit de l'IA ?

# R3 — Fournisseurs → modèles & switch rapide — Design

- **Date** : 2026-06-23
- **Statut** : design (validé au brainstorming v2) — en attente de relecture avant plan
- **Contexte** : 4ᵉ étape de la refonte v2. Passer du « clé brute par fournisseur » au modèle **fournisseur + clé + choix du modèle** (style SuperWhisper), avec **bascule rapide du modèle** sur l'Accueil.

## 1. Vision & périmètre
Chaque **fournisseur** (Apple, ElevenLabs, Mistral, OpenAI) expose une **liste de modèles** ; on en **sélectionne un** (persisté par fournisseur). Les **Réglages** configurent fournisseur + clé + modèle ; l'**Accueil** permet de **changer rapidement** le moteur/modèle actif.

**Modèles (recherche juin 2026) :**
- **Apple (local)** : 1 modèle on-device (« Apple — sur l'appareil »). Pas de clé.
- **ElevenLabs** : `scribe_v2` (« Scribe v2 »). *(scribe_v1 déprécié, exclu ; realtime = endpoint séparé, hors batch.)*
- **Mistral** : `voxtral-mini-latest` (« Voxtral Mini Transcribe »).
- **OpenAI** : `gpt-4o-transcribe` (défaut), `gpt-4o-mini-transcribe`, `whisper-1`. *(diarize reporté : réponse différente.)*

**Dans R3 :**
- `EngineModel` (id API + nom affiché) + liste de modèles par fournisseur + modèle par défaut.
- `makeEngine(apiKey:modelId:transport:)` : construit le moteur avec le **modèle choisi**.
- `CloudTranscriptionEngine` : le `modelId` passé prime sur `config.modelValue`.
- Réglages : par fournisseur → clé + **sélecteur de modèle**.
- Accueil : **menu de bascule rapide** (fournisseur + modèle actifs) → reconstruit le service à chaud.

**Hors R3 :** Fichiers (R4) · refonte règles (R5) · motion (R6) · diarisation/realtime.

## 2. Architecture / composants
| Composant | Rôle | Emplacement |
|---|---|---|
| `EngineModel` | `{ id: String, displayName: String }` (id = chaîne API) | FlowScribeCore |
| `EngineProvider.models` / `defaultModelId` | liste de modèles par fournisseur | FlowScribeCore (étendu) |
| `EngineProvider.makeEngine(apiKey:modelId:transport:)` | construit le moteur avec le modèle choisi | FlowScribeCore (signature étendue) |
| `CloudTranscriptionEngine` | `init(config:apiKey:transport:modelId:)` — `modelId` prime sur `config.modelValue` | FlowScribeCore (étendu) |
| `SettingsStore` | `selectedModelId(for:)` / `setModel(_:for:)` (UserDefaults par fournisseur) | app |
| `SettingsView` | par fournisseur : clé + Picker de modèle | app |
| `HomeView` / `EnginePickerView` | menu de bascule rapide (fournisseur + modèle) | app |
| `FlowScribeApp.makeService` | utilise `provider` + `selectedModelId(for: provider)` | app (modifié) |

- Modèles définis comme **données** (statics) dans `EngineProvider`/`CloudEngineConfig` — pas en dur dans l'UI.
- Apple : `models = [EngineModel(id: "apple", displayName: "Apple — sur l'appareil")]` ; `makeEngine` ignore `modelId` (renvoie `AppleSpeechEngine`).

## 3. Sélection & persistance
- `SettingsStore.selectedModelId(for provider) -> String` : lit UserDefaults `model.<provider>` ; défaut = `provider.defaultModelId`.
- `setModel(id, for:)` : persiste + déclenche `onChange` (reconstruction du service à chaud).
- L'« actif » = (`defaultProvider`, `selectedModelId(for: defaultProvider)`).

## 4. UI
- **Réglages → Fournisseurs** : pour chaque fournisseur cloud : champ clé (+ Tester, existant) **+ Picker** « Modèle ». Apple : juste « sur l'appareil ».
- **Accueil** : remplacer la pastille lecture-seule par un **menu** : choisir le **fournisseur** actif, puis son **modèle**. Changement → `onChange` → service reconstruit (déjà en place).

## 5. Tests
- **TDD** : `EngineProvider.models`/`defaultModelId` (valeurs attendues : openAI a 3 modèles, elevenLabs `scribe_v2`, etc.) ; `makeEngine(modelId:)` → l'engine porte le bon `id`/utilise le bon modèle ; `CloudTranscriptionEngine` avec `modelId` → la requête contient ce modèle (MockTransport).
- **Build + recette** : Réglages (picker modèle), Accueil (bascule rapide), dictée avec le modèle choisi.

## 6. Risques / à vérifier
- IDs de modèles : `voxtral-mini-latest`, `scribe_v2`, `gpt-4o-transcribe`/`-mini`/`whisper-1` confirmés ; `-latest` suit la dernière version. À reconfirmer si une API évolue.
- `whisper-1`/`gpt-4o-*` renvoient `{text}` (compatibles notre parsing) ; diarize exclu (réponse différente).
- Migration douce : si aucun modèle persisté, on prend `defaultModelId` (pas de rupture pour les clés déjà saisies).

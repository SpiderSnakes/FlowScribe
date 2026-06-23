# R1 — Coquille & navigation latérale — Design

- **Date** : 2026-06-23
- **Statut** : design (IA validée au brainstorming v2) — en attente de relecture avant plan
- **Contexte** : 2ᵉ étape de la refonte v2. Remplace la fenêtre vide + la fenêtre Réglages (⌘,) par une **vraie app à sidebar** Liquid Glass bleue.

## 1. Vision & périmètre

Transformer FlowScribe en application structurée : une **fenêtre principale** avec **navigation latérale** (NavigationSplitView), thème bleu Liquid Glass. On **relocalise** les écrans existants (Glossaire, Calibration, Réglages) dans la sidebar et on pose une page **Accueil**.

**Dans R1 :**
- Fenêtre principale = `NavigationSplitView` : **sidebar** à gauche + **détail** à droite.
- Sidebar (haut) : **Accueil**, **Vocabulaire**. Sidebar (bas, épinglé) : **Réglages**.
- **Accueil** : page d'atterrissage — rappel du raccourci ⌥Espace + **gros bouton d'enregistrement**, pastille « moteur actif » (lecture seule pour l'instant), et **emplacement réservé** « Tes transcriptions apparaîtront ici » (l'historique arrive en R2).
- **Vocabulaire** : `GlossaryView` (termes + règles par moteur) + bouton **« Calibrer un moteur »** qui présente `CalibrationView` en feuille (sheet). *(Fusion légère ; la refonte profonde des règles = R5.)*
- **Réglages** : `SettingsView` existant (moteur défaut, clés, langue, confort, autorisations), **dans la sidebar** — on **supprime la fenêtre Réglages séparée**.
- **Localisation FR/EN** des menus système (« À propos de FlowScribe », « Quitter FlowScribe », Fichier…) : l'app déclare les localisations `en` + `fr` → macOS traduit les menus standards selon la langue du Mac.
- Thème bleu (R0) étendu à la sidebar/au fond.

**Hors R1 (étapes suivantes) :** historique réel (R2) · fournisseurs→modèles + switch rapide sur l'Accueil (R3) · onglet **Fichiers** (R4) · refonte des règles « Vocabulaire » globales/par-modèle + activation (R5) · motion global (R6).

## 2. Architecture / composants

| Composant | Rôle | Emplacement |
|---|---|---|
| `AppSection` | enum des sections (`accueil`, `vocabulaire`, `reglages`) | app |
| `RootView` | `NavigationSplitView` (sidebar + détail), porte la sélection | app |
| `SidebarView` | liste Liquid Glass : items haut + Réglages épinglé en bas | app |
| `HomeView` | Accueil (hero : bouton d'enregistrement, pastille moteur, placeholder historique) | app |
| `VocabularyView` | hôte de `GlossaryView` + bouton « Calibrer » (sheet `CalibrationView`) | app |
| `GlossaryView`, `CalibrationView`, `SettingsView`, `PermissionsView` | réutilisés tels quels | app (existants) |
| `FlowScribeApp` | `WindowGroup { RootView(...) }`, **plus de scène `Settings`** ; `MenuBarExtra` conservé ; `setup()` (controller/HUD/services) inchangé, déplacé dans `RootView.task` | app |

- `RootView` reçoit les dépendances existantes (`settings`, `permissions`, `glossary`, `profiles`) en paramètres ; le `setup()` (création recorder+HUD+controller+bridge, câblage niveau, onChange) est déplacé tel quel dans `RootView`.
- Sélection : `@State private var section: AppSection = .accueil`.

## 3. Sidebar (détails)
- Items haut : Accueil (icône `house`), Vocabulaire (`text.book.closed`).
- Bas (épinglé) : Réglages (`gearshape`) — via un `Spacer()` dans la sidebar pour le pousser en bas.
- Style : fond Liquid Glass, sélection en accent bleu (`Theme.accent`), `.tint(Theme.accent)`.

## 4. Accueil (R1, sans historique réel)
- Hero centré : titre + sous-titre « Appuie sur ⌥Espace pour dicter ».
- **Bouton d'enregistrement** rond (déclenche/arrête une dictée via le contrôleur).
- Pastille **« Moteur : \<nom\> »** (lecture seule en R1 ; le switch rapide = R3).
- Bloc placeholder « Tes transcriptions récentes apparaîtront ici » (rempli en R2).
- Si autorisations manquantes : on garde l'onboarding `PermissionsView` (inline, comme aujourd'hui).

## 5. Localisation
- Déclarer `en` + `fr` dans les localisations de l'app (knownRegions + `en.lproj`/`fr.lproj` avec `InfoPlist.strings`), `CFBundleDevelopmentRegion = fr` ou `en`.
- Résultat : les menus AppKit standards (À propos / Masquer / Quitter / Édition…) se traduisent automatiquement selon la langue système.

## 6. Tests
- Pas de logique métier nouvelle → **build + recette visuelle** : navigation entre sections, Réglages dans la sidebar (plus de ⌘, séparé), dictée depuis l'Accueil, menus système en français sur un Mac FR.
- (Le cœur testé reste inchangé : 52/52.)

## 7. Risques / à vérifier
- `NavigationSplitView` + `MenuBarExtra` + suppression de la scène `Settings` : vérifier qu'aucun comportement ⌘, cassé ne gêne (option : intercepter ⌘, pour sélectionner Réglages — nice-to-have, hors R1).
- Localisation via XcodeGen (chemins `.lproj`) : à valider au build ; repli = au moins `CFBundleDevelopmentRegion`/`CFBundleLocalizations` dans l'Info.
- Le `setup()` déplacé dans `RootView.task` ne doit s'exécuter qu'une fois (garde `controller == nil`).

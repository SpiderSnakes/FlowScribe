# Rebranding « Voix → Lumière » — Cahier de design

**Date** : 2026-06-25
**Statut** : validé (direction), en attente de relecture du cahier détaillé
**Périmètre** : refonte de l'identité visuelle de FlowScribe (onboarding + app), inspirée de 6 références React Bits, traduites en SwiftUI/Metal natif (macOS 26).

---

## 1. Intention

FlowScribe transforme la **voix en texte**. L'identité visuelle raconte ça : **le son devient des fils lumineux** qui ondulent sur une nuit profonde, grainée, traversée d'aurores. La lumière n'apparaît qu'aux moments forts ; le reste du temps l'app est calme et lisible (c'est un outil de dictée qui tourne en arrière-plan).

Principe directeur : **un motif signature, un socle commun, la lumière en accents.**

## 2. Jeu d'effets retenu (et hiérarchie)

| Rôle | Effet (réf. React Bits) | Idée retenue |
|---|---|---|
| **Signature** | Strands | Fils lumineux qui ondulent = la voix rendue visible. Déjà amorcé dans le HUD. |
| **Socle** | Grainient | Dégradé profond + grain fin = base mate, premium, tactile. Fond commun de tous les écrans. |
| **Accent — ambiance** | Aurora | Rubans de couleur qui dérivent, flous, additifs. |
| **Accent — lumière** | Side Rays | Faisceaux de lumière depuis un bord. |
| **Accent — focus** | Border Glow | Contour lumineux animé sur les éléments actifs/CTA. |
| **Écarté** | Gradient Blinds | Trop « rétro/tech », casse la cohérence. Non retenu. |

## 3. Palettes (3 presets, choisis dans Réglages → Apparence)

L'UI et le texte restent **neutres** (blanc/gris) dans tous les presets. La palette ne pilote que les **accents** : aurores, strands, glows, rays. Valeurs indicatives (ajustables à l'œil pendant l'implémentation, mais ce sont les valeurs de départ).

### Rôles de couleur communs à tous les presets
- `textPrimary` = blanc 92 % · `textSecondary` = blanc 60 % · `hairline` = blanc 14 %
- `base` / `baseTop` = les 2 bornes du dégradé de fond (sombre).

### Preset A — « Nuit bleue » *(défaut, continuité avec l'existant)*
- `base` `#060A1A` → `baseTop` `#0A1430`
- `accentPrimary` `#5B8DEF` (bleu actuel) · `accentSecondary` `#7C6CFF` (violet) · `accentTertiary` `#3FE0D0` (cyan)
- `warm` (erreurs/accents) `#FF8A5C`

### Preset B — « Aurore froide »
- `base` `#040712` → `baseTop` `#091126`
- `accentPrimary` `#3A7BFF` · `accentSecondary` `#9A5CFF` · `accentTertiary` `#2BE7B0` · `accentQuaternary` `#18C2FF`
- `warm` `#FF7A4D`

### Preset C — « Aurore duale »
- Base + froids = identiques à « Aurore froide ».
- Ajout chaud, **réservé aux états d'erreur et accents ponctuels** : `warmPrimary` `#FF5C8A` · `warmSecondary` `#FFB23F`

**Défaut produit** : « Nuit bleue » (évolution douce de l'identité actuelle). L'utilisateur change dans Réglages.

## 4. Intensité (3 crans, choisis dans Réglages → Apparence)

La « jauge d'intensité » déjà souhaitée. Défaut : **Équilibré**.

| Cran | Onboarding | HUD | App (accueil/réglages/détail/clés) |
|---|---|---|---|
| **Discret** | grainient + strands légers (statique/quasi) | strands animés | statique ; glow uniquement sur l'action de dictée |
| **Équilibré** *(défaut)* | tout animé (aurora + rays + strands) | strands animés + glow | grainient statique + glows ponctuels ; **anim. en pause si fenêtre inactive** |
| **Showcase** | tout animé | strands animés + glow | aurora + strands animés partout |

**Garde-fous transversaux (toujours actifs)** :
- Respect de **« Réduire les animations »** du système → repli entièrement statique, quel que soit le cran.
- Les animations de la **fenêtre principale** se mettent en pause quand elle n'est pas active/visible (sauf en Showcase). Le **HUD** est une fenêtre à part : ses strands animent pendant l'enregistrement quel que soit le focus.

## 5. Application surface par surface

| Surface | Changements |
|---|---|
| **Onboarding** | Refonte plein écran « waouh » : socle grainient + **aurora** qui dérive + **side-rays** depuis un bord + **strands** en filigrane. Les étapes de permission flottent dans des cartes à `.borderGlow()`. C'est le moment le plus animé de l'app. |
| **HUD (Classic + Mini)** | Strands déjà en place → **couleurs alignées sur la palette active** ; ajout d'un **border-glow** doux sur le panneau pendant l'enregistrement. (Pas de régression sur les correctifs récents : coins transparents, lissage 60fps, timer `.common`.) |
| **Accueil** | Socle grainient ; **aurora** très estompée derrière le titre « Historique » ; **border-glow** sur le bouton « Dicter » et sur le chip du mode actif ; bord lumineux discret sur la carte survolée/sélectionnée. |
| **Détail transcription** | Socle grainient ; l'état d'erreur (déjà orange) se branche sur l'accent `warm` de la palette. |
| **Réglages** | Socle grainient + **nouvelle section « Apparence »** : sélecteur de palette (3 vignettes) + sélecteur d'intensité (3 crans). |
| **Clés API** | La ligne de fournisseur **en édition** reçoit un `.borderGlow()` (renforce le focus de la refonte récente). |
| **Sidebar** | Matériau translucide conservé, **teinté** par la palette active (au lieu du gris neutre). |

## 6. Architecture

### 6.1 État & source de vérité
- `SettingsStore` gagne deux réglages persistés (UserDefaults, comme les autres) :
  - `ambiancePalette: AmbiancePalette` (`enum`: `.nuitBleue`, `.auroreFroide`, `.auroreDuale`) — défaut `.nuitBleue`.
  - `ambianceIntensity: AmbianceIntensity` (`enum`: `.discret`, `.equilibre`, `.showcase`) — défaut `.equilibre`.
- `BrandPalette` : `struct` qui mappe un `AmbiancePalette` vers un **jeu de rôles fixe** : `base`, `baseTop`, `accentPrimary`, `accentSecondary`, `accentTertiary`, `accentQuaternary`, `warm`, `warmSecondary`, `hairline`, `textPrimary`, `textSecondary`. Les rôles non définis par un preset retombent sur un défaut explicite (`accentQuaternary ?? accentPrimary`, `warmSecondary ?? warm`) — ainsi toute vue peut référencer n'importe quel rôle sans condition. L'aurora consomme `[accentPrimary, accentSecondary, accentTertiary, accentQuaternary]`. Pur, **testable**.
- `Ambiance` : petit objet observable (palette résolue + politique d'animation) injecté dans l'environnement SwiftUI. Les vues le lisent ; changer un réglage met tout à jour en direct.
- `Theme.swift` : refactor pour **dériver** ses couleurs d'accent de la palette active. Les constantes purement neutres (hairline, etc.) restent partagées. (Refactor ciblé, pas de réécriture globale.)

### 6.2 Briques réutilisables (nouveaux fichiers, une responsabilité chacune)
- `GrainientBackground` (View) — dégradé `base→baseTop` + grain. Grain via un **SwiftUI `Shader` Metal** (`.colorEffect`/`.layerEffect`, `ShaderLibrary`) ; **repli** = image de bruit pré-rendue tilée en `.overlay` faible opacité si le shader pose souci de toolchain. Le grain peut être statique (perf) ou très lentement animé selon l'intensité.
- `AuroraView` (View) — `MeshGradient` (macOS 26) aux points de contrôle animés par `TimelineView` + `.blur`, couleurs = accents de la palette.
- `StrandsView` (View) — généralisation de l'actuel rendu HUD (`Canvas` + `TimelineView`) en composant paramétrable (densité, vitesse, opacité, amplitude, palette). Réutilisé par le HUD et par l'onboarding (plus lent, plus discret, plein écran).
- `SideRaysView` (View) — cône de gradients linéaires/`AngularGradient` depuis un bord + `.blur` + léger shimmer temporel.
- `.borderGlow(active:cornerRadius:)` (ViewModifier) — `AngularGradient` en `strokeBorder` tourné par `TimelineView`, + halo flou derrière. S'éteint (statique) si animations désactivées.

### 6.3 Politique d'animation (un seul point de décision)
- Une fonction unique `Ambiance.animates(_ surface: AmbianceSurface) -> Bool` où `surface ∈ {onboarding, hud, appWindow}`.
- Résultat = matrice du §4 **ET** `!reduceMotion` **ET** (pour `appWindow`) `windowIsActive`.
- `reduceMotion` lu via l'environnement SwiftUI (`accessibilityReduceMotion`).
- `windowIsActive` via les notifications de la fenêtre principale (`NSWindow` key/visible) ou l'environnement de scène.
- Tous les `TimelineView` des briques sont **gardés** par ce drapeau → zéro GPU quand l'app dort.

### 6.4 Réutilisation de l'existant
- Les strands du HUD (`HUDWaveform`/`ClassicHUDView`) deviennent le socle de `StrandsView`.
- `VisualEffectBackground` conservé pour la sidebar (teinté).
- Les correctifs récents (HUD, robustesse) ne sont pas touchés.

## 7. Performance & accessibilité (exigences)
- **Aucune animation** quand : reduce-motion système actif, ou fenêtre principale inactive (hors Showcase), ou cran Discret sur les surfaces concernées.
- Densité/fps des effets plein écran (onboarding strands/aurora) calibrés pour rester fluides ; en cas de doute, baisser densité avant fps.
- Le grain par défaut est **statique** (coût quasi nul) ; animation du grain réservée à Showcase.
- Cible : pas de hausse de conso notable en usage normal (app en fond, fenêtre fermée → 0 effet actif).

## 8. Ce qui est testable (unitaire, dans FlowScribeCore quand pertinent)
- `BrandPalette` : chaque `AmbiancePalette` mappe vers les rôles attendus (valeurs non nulles, cohérentes).
- `Ambiance.animates(surface:)` : la matrice §4 × reduce-motion × window-active renvoie les bons booléens (table de vérité).
- Persistance : `ambiancePalette`/`ambianceIntensity` encodent/décodent et survivent à un relancement (valeurs par défaut si absentes).
- Les effets visuels eux-mêmes ne sont pas testés unitairement (validation à l'œil).

## 9. Ordre de construction (phases — détail dans le plan)
1. **Socle Ambiance** : enums + `BrandPalette` + `Ambiance` + persistance + section Réglages·Apparence + `animates()`. (Testable, invisible mais fondateur.)
2. **`GrainientBackground`** appliqué à tous les écrans (gros impact visuel, faible coût) ; `Theme` dérivé de la palette.
3. **Briques lumière** : `AuroraView`, `SideRaysView`, `.borderGlow()`.
4. **Refonte onboarding** (assemble tout — le moment « waouh »).
5. **Application aux surfaces** (accueil, HUD aligné palette + glow, détail, clés API, sidebar) + passe perf/reduce-motion/window-active.

## 10. Hors périmètre (pour l'instant)
- Refonte du **wordmark/logo** (un fil lumineux formant la marque) : idée notée, à décider plus tard, pas dans ce lot.
- **Gradient Blinds** : écarté.
- Thèmes clairs (light mode) : l'app est nocturne par nature ; non couvert ici.
- Sons/haptique : hors sujet visuel.

## 11. Risques & parades
- **Toolchain Metal** (`.metal` à inclure via XcodeGen) : si friction, le grain et les effets retombent sur des solutions SwiftUI pures (image de bruit, `MeshGradient`, `Canvas`, gradients) — aucun effet ne dépend *exclusivement* d'un shader custom.
- **Cohérence** : risque de « sapin de Noël » si tout brille. Parade : hiérarchie stricte (§2) + intensité par défaut Équilibré + lumière réservée aux moments/éléments clés.
- **Lisibilité** : les accents ne doivent jamais passer sous le texte utile à pleine opacité (aurora/strands toujours estompés derrière le contenu).

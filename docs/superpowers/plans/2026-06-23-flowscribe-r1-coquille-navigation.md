# R1 — Coquille & navigation — Plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development ou executing-plans. (Cette session : exécution inline.)

**Goal:** Remplacer la fenêtre vide + la fenêtre Réglages par une app à **sidebar Liquid Glass** (Accueil / Vocabulaire + Réglages épinglé en bas), avec menus système localisés FR/EN.

**Architecture:** `RootView` = `NavigationSplitView` (sidebar custom + détail). La sélection (`AppSection`) route vers `HomeView`, `VocabularyView` (= Glossaire + bouton Calibrer en sheet), ou `SettingsView` (existant). `FlowScribeApp` héberge `RootView`, conserve l'orchestration (setup/controller/HUD), supprime la scène `Settings`.

**Tech Stack:** Swift 6, SwiftUI (`NavigationSplitView`, `glassEffect`), FlowScribeCore (réutilisé), XcodeGen.

## Global Constraints
- macOS 26+, Apple Silicon, Swift 6.
- Thème bleu (`Theme`) réutilisé ; accent `Theme.accent`.
- **Pas de nouvelle logique métier** → build + recette visuelle (cœur reste 52/52).
- Réglages **dans la sidebar** (plus de fenêtre `Settings` séparée).
- Vocabulaire = fusion légère (Glossaire + bouton Calibrer) ; refonte profonde = R5.
- Accueil sans historique réel (R2) ni switch modèle (R3) : placeholder + pastille lecture seule.
- Commits fréquents (français + trailer), push sur `origin r1-coquille-navigation`.

## Structure de fichiers
```
FlowScribe/
├── AppSection.swift       enum des sections de navigation
├── SidebarView.swift      sidebar custom (items haut + Réglages bas)
├── RootView.swift         NavigationSplitView (sidebar + détail)
├── HomeView.swift          Accueil (bouton d'enregistrement, pastille moteur, placeholder)
├── VocabularyView.swift    Glossaire + bouton Calibrer (sheet)
├── GlossaryView.swift / SettingsView.swift  (modifiés : retrait des .frame fixes)
└── FlowScribeApp.swift     (modifié : WindowGroup { RootView }, suppression scène Settings, toggleRecord)
```

---

### Task 1: Coquille de navigation (sidebar + RootView + écrans)
**Files:** Create `AppSection.swift`, `SidebarView.swift`, `RootView.swift`, `HomeView.swift`, `VocabularyView.swift` ; Modify `GlossaryView.swift`, `SettingsView.swift` (retrait `.frame` fixe), `FlowScribeApp.swift`.
**Interfaces:**
- Produces: `enum AppSection` ; `SidebarView(section:)` ; `RootView(settings:permissions:glossary:profiles:onToggleRecord:)` ; `HomeView(...)` ; `VocabularyView(...)`.
> UI : build + recette visuelle.

- [ ] **Step 1: `AppSection.swift`**
```swift
import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case accueil, vocabulaire, reglages
    var id: String { rawValue }
    var title: String {
        switch self {
        case .accueil: return "Accueil"
        case .vocabulaire: return "Vocabulaire"
        case .reglages: return "Réglages"
        }
    }
    var icon: String {
        switch self {
        case .accueil: return "house"
        case .vocabulaire: return "text.book.closed"
        case .reglages: return "gearshape"
        }
    }
}
```

- [ ] **Step 2: `SidebarView.swift`**
```swift
import SwiftUI

struct SidebarView: View {
    @Binding var section: AppSection
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach([AppSection.accueil, .vocabulaire]) { row($0) }
            Spacer()
            row(.reglages)
        }
        .padding(8)
    }
    private func row(_ s: AppSection) -> some View {
        Button { section = s } label: {
            Label(s.title, systemImage: s.icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(section == s ? Theme.accent.opacity(0.22) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(section == s ? Theme.accent : .primary)
    }
}
```

- [ ] **Step 3: `VocabularyView.swift`**
```swift
import SwiftUI
import FlowScribeCore

struct VocabularyView: View {
    let glossary: GlossaryStore
    let profiles: CorrectionProfileStore
    let settings: SettingsStore
    @State private var showCalibration = false

    var body: some View {
        VStack(spacing: 0) {
            GlossaryView(glossary: glossary, profiles: profiles)
            Divider()
            Button("Calibrer un moteur") { showCalibration = true }
                .buttonStyle(.glass)
                .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showCalibration) {
            CalibrationView(glossary: glossary, profiles: profiles, settings: settings)
        }
    }
}
```

- [ ] **Step 4: `HomeView.swift`**
```swift
import SwiftUI
import FlowScribeCore

struct HomeView: View {
    let settings: SettingsStore
    let permissions: PermissionsModel
    let onToggleRecord: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            if !permissions.allGranted {
                PermissionsView(model: permissions)
                Divider()
            }
            Spacer()
            Text("FlowScribe").font(.largeTitle.bold())
            Text("Appuie sur ⌥Espace — ou le bouton — pour dicter.")
                .foregroundStyle(.secondary)
            Button(action: onToggleRecord) {
                Image(systemName: "mic.fill").font(.system(size: 28))
                    .frame(width: 88, height: 88)
            }
            .buttonStyle(.glassProminent)
            .clipShape(Circle())
            Text("Moteur : \(settings.defaultProvider.displayName)")
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
            Spacer()
            Text("Tes transcriptions récentes apparaîtront ici (bientôt).")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 5: `RootView.swift`**
```swift
import SwiftUI
import FlowScribeCore

struct RootView: View {
    let settings: SettingsStore
    let permissions: PermissionsModel
    let glossary: GlossaryStore
    let profiles: CorrectionProfileStore
    let onToggleRecord: () -> Void

    @State private var section: AppSection = .accueil

    var body: some View {
        NavigationSplitView {
            SidebarView(section: $section)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            switch section {
            case .accueil:
                HomeView(settings: settings, permissions: permissions, onToggleRecord: onToggleRecord)
            case .vocabulaire:
                VocabularyView(glossary: glossary, profiles: profiles, settings: settings)
            case .reglages:
                SettingsView(settings: settings, permissions: permissions)
            }
        }
        .tint(Theme.accent)
    }
}
```

- [ ] **Step 6: Retirer les `.frame` fixes** dans `GlossaryView.swift` et `SettingsView.swift` pour qu'ils remplissent le panneau de détail.
  - `GlossaryView` : remplacer `.frame(width: 480, height: 480)` par `.frame(maxWidth: .infinity, maxHeight: .infinity)`.
  - `SettingsView` : remplacer `.frame(width: 470, height: 500)` par `.frame(maxWidth: .infinity, maxHeight: .infinity)`.

- [ ] **Step 7: Réécrire `FlowScribeApp.swift`** — héberger `RootView`, supprimer la scène `Settings`, ajouter `toggleRecord()`. Remplacer le `body` et ajouter la méthode (le reste : `setup`, `makeService`, `applyOptions`, `makeCleanup` inchangés) :
```swift
    var body: some Scene {
        WindowGroup("FlowScribe") {
            RootView(settings: settings, permissions: permissions,
                     glossary: glossary, profiles: profiles,
                     onToggleRecord: { toggleRecord() })
                .frame(minWidth: 720, minHeight: 480)
                .task { await setup() }
        }
        MenuBarExtra("FlowScribe", systemImage: "mic.fill") {
            Button("Quitter") { NSApplication.shared.terminate(nil) }
        }
    }

    @MainActor
    private func toggleRecord() {
        guard let c = controller else { return }
        c.pressDown()
        Task { await c.pressUp(kind: .tap) }
    }
```
(Supprimer la scène `Settings { TabView { … } }`.)

- [ ] **Step 8: Build** `xcodegen generate && xcodebuild -project FlowScribe.xcodeproj -scheme FlowScribe -destination 'platform=macOS' build` → SUCCEEDED.
- [ ] **Step 9: Commit** `feat(r1): coquille NavigationSplitView (sidebar Accueil/Vocabulaire + Réglages bas)`.

---

### Task 2: Localisation FR/EN des menus système
**Files:** Modify `project.yml` (Info).
> Build + recette (Mac en français → menus traduits).

- [ ] **Step 1: Déclarer les localisations** — dans `project.yml`, sous `targets.FlowScribe.info.properties`, ajouter :
```yaml
        CFBundleDevelopmentRegion: en
        CFBundleLocalizations:
          - en
          - fr
```
- [ ] **Step 2: Build** `xcodegen generate && xcodebuild … build` → SUCCEEDED.
- [ ] **Step 3: Recette** (PORTE HUMAINE) : sur un Mac en **français**, vérifier que le menu app affiche « À propos de FlowScribe », « Masquer FlowScribe », « Quitter FlowScribe », et « Édition/Fichier » traduits.
- [ ] **Step 4: Commit** `feat(r1): localisation FR/EN des menus système`.

---

## Auto-revue (à l'écriture)
- **Couverture spec** : sidebar Accueil/Vocabulaire + Réglages bas (T1) · Accueil hero+placeholder (T1) · Vocabulaire=Glossaire+Calibrer (T1) · Réglages dans la sidebar, scène Settings supprimée (T1) · localisation (T2) · thème bleu (réutilisé). ✅
- **Hors R1** : historique réel (R2), switch modèle (R3), Fichiers (R4), refonte règles (R5), motion (R6).
- **Placeholders** : aucun ; code complet. Pas de TDD (UI pure) → recette visuelle.
- **Cohérence types** : `AppSection`, `SidebarView(section:)`, `RootView(settings:permissions:glossary:profiles:onToggleRecord:)`, `HomeView(settings:permissions:onToggleRecord:)`, `VocabularyView(glossary:profiles:settings:)`, `toggleRecord()` cohérents ; réutilise `DictationController.pressDown()/pressUp(kind:)`.
- **Risque** : suppression de la scène `Settings` → ⌘, n'ouvre plus rien (acceptable ; Réglages via sidebar).

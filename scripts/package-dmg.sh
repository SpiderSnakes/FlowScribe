#!/usr/bin/env bash
set -euo pipefail

# Packaging FlowScribe en DMG signé + notarisé (Developer ID, hardened runtime).
#
# Prérequis (UNE SEULE FOIS) — créer un profil de credentials notarytool :
#   xcrun notarytool store-credentials claude-usage-notary \
#     --apple-id "<ton-apple-id>" \
#     --team-id Y8XLVL2758 \
#     --password "<mot-de-passe-app-spécifique>"   # https://appleid.apple.com -> Sécurité
#
# Puis lancer :  ./scripts/package-dmg.sh
# (override du profil : FLOWSCRIBE_NOTARY_PROFILE=autre ./scripts/package-dmg.sh)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROFILE="${FLOWSCRIBE_NOTARY_PROFILE:-claude-usage-notary}"
IDENTITY="${FLOWSCRIBE_SIGN_IDENTITY:-Developer ID Application: Cyprien RIVIERE--CACHAU (Y8XLVL2758)}"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/Build/Products/Release/FlowScribe.app"

# Version courte (0.1.0 -> 0.1) déduite de project.yml pour nommer le DMG.
VERSION="$(grep -m1 'MARKETING_VERSION' project.yml | sed 's/.*"\(.*\)".*/\1/')"
SHORT="${VERSION%.0}"
DMG="$ROOT/FlowScribe-${SHORT}.dmg"

echo "==> Génération du projet (XcodeGen)"
xcodegen generate

echo "==> Build Release (Developer ID, hardened runtime) — v$VERSION"
xcodebuild -project FlowScribe.xcodeproj -scheme FlowScribe -configuration Release \
  -derivedDataPath "$BUILD_DIR" -destination 'platform=macOS' clean build

[ -d "$APP" ] || { echo "ERREUR : app introuvable à $APP"; exit 1; }

# Re-signature de distribution (déterministe) : xcodebuild peut produire une signature SANS horodatage
# sécurisé et AVEC l'entitlement de débogage « get-task-allow » → notarisation refusée. On re-signe avec
# le runtime durci (--options runtime), un horodatage sécurisé (--timestamp) et le fichier d'entitlements
# de prod (qui ne contient PAS get-task-allow → l'entitlement de débogage est retiré). L'app est
# autonome (KeyboardShortcuts est lié statiquement via SPM, aucun framework embarqué à re-signer).
# Re-signature AVEC RÉESSAIS : le serveur d'horodatage Apple (TSA) échoue parfois de façon transitoire ;
# codesign produit alors une signature SANS horodatage sécurisé tout en sortant 0 → notarisation refusée.
# On réessaie jusqu'à ce que l'horodatage soit RÉELLEMENT présent dans la signature.
echo "==> Re-signature de distribution de l'app (horodatage sécurisé)"
resign_ok=0
for attempt in $(seq 1 8); do
  codesign --force --options runtime --timestamp \
    --entitlements "$ROOT/FlowScribe/FlowScribe.entitlements" \
    --sign "$IDENTITY" "$APP" 2>&1 || true
  if codesign -dvvv "$APP" 2>&1 | grep -q "Timestamp="; then resign_ok=1; break; fi
  wait_s=$(( attempt * 4 )); [ "$wait_s" -gt 20 ] && wait_s=20   # backoff doux (évite le rate-limit TSA)
  echo "  ⚠️  horodatage absent (tentative $attempt/8) — réessai dans ${wait_s}s (TSA Apple indisponible)…"
  sleep "$wait_s"
done
[ "$resign_ok" = 1 ] || { echo "ERREUR : horodatage sécurisé impossible après 8 tentatives — réessaie plus tard (serveur Apple)"; exit 1; }

echo "==> Vérification de la signature de l'app"
codesign --verify --deep --strict --verbose=2 "$APP"
if codesign -d --entitlements - "$APP" 2>/dev/null | tr -d '\0' | grep -q "get-task-allow"; then
  echo "ERREUR : l'entitlement de débogage get-task-allow est toujours présent"; exit 1
fi

echo "==> Assemblage du DMG d'installation : $(basename "$DMG")"
VOLNAME="FlowScribe"
STAGE="$(mktemp -d)"
RW_DMG="$(mktemp -u).dmg"
# Contenu : l'app + un raccourci vers /Applications (glisser-déposer) + le fond d'écran.
cp -R "$APP" "$STAGE/FlowScribe.app"
ln -s /Applications "$STAGE/Applications"
mkdir -p "$STAGE/.background"
cp "$ROOT/scripts/dmg-background.png" "$STAGE/.background/background.png"

# DMG lecture-écriture dimensionné au contenu (pour pouvoir poser la mise en page Finder).
rm -f "$RW_DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW_DMG"

# Démonte un éventuel volume résiduel, puis monte (visible par Finder pour le scripter).
hdiutil detach "/Volumes/$VOLNAME" >/dev/null 2>&1 || true
hdiutil attach "$RW_DMG" -noautoopen >/dev/null

# Mise en page Finder (best-effort : nécessite l'autorisation « contrôler Finder » la 1re fois ;
# si refusée, le DMG reste fonctionnel — app + raccourci Applications — mais sans la mise en page).
osascript <<OSA || echo "  ⚠️  mise en page Finder ignorée (autorisation « contrôler Finder » manquante ?)"
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 548}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set background picture of opts to file ".background:background.png"
    set position of item "FlowScribe.app" of container window to {150, 200}
    set position of item "Applications" of container window to {450, 200}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA

sync
hdiutil detach "/Volumes/$VOLNAME" >/dev/null 2>&1 || hdiutil detach "/Volumes/$VOLNAME" -force >/dev/null 2>&1 || true

# Conversion finale en lecture seule compressée.
rm -f "$DMG"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -rf "$STAGE" "$RW_DMG"

echo "==> Signature du DMG (Developer ID)"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

echo "==> Notarisation (profil keychain : $PROFILE)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "==> Agrafage (stapler)"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "==> Vérification Gatekeeper finale"
spctl --assess --type open --context context:primary-signature -v "$DMG" || true

echo "✅ DMG signé + notarisé prêt : $DMG"

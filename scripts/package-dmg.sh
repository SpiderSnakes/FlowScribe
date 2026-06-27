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
echo "==> Re-signature de distribution de l'app"
codesign --force --options runtime --timestamp \
  --entitlements "$ROOT/FlowScribe/FlowScribe.entitlements" \
  --sign "$IDENTITY" "$APP"

echo "==> Vérification de la signature de l'app"
codesign --verify --deep --strict --verbose=2 "$APP"
# Garde-fous : échouer TÔT si l'horodatage manque ou si get-task-allow est encore présent.
codesign -dvvv "$APP" 2>&1 | grep -q "Timestamp=" || { echo "ERREUR : horodatage sécurisé absent"; exit 1; }
if codesign -d --entitlements - "$APP" 2>/dev/null | tr -d '\0' | grep -q "get-task-allow"; then
  echo "ERREUR : l'entitlement de débogage get-task-allow est toujours présent"; exit 1
fi

echo "==> Création du DMG : $(basename "$DMG")"
rm -f "$DMG"
hdiutil create -volname "FlowScribe" -srcfolder "$APP" -ov -format UDZO "$DMG"

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

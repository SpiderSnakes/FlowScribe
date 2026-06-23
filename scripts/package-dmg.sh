#!/usr/bin/env bash
set -euo pipefail

# Packaging FlowScribe en DMG notarisé (Developer ID, hardened runtime).
#
# Prérequis (UNE SEULE FOIS) — créer un profil de credentials notarytool :
#   xcrun notarytool store-credentials flowscribe-notary \
#     --apple-id "<ton-apple-id>" \
#     --team-id Y8XLVL2758 \
#     --password "<mot-de-passe-app-spécifique>"   # https://appleid.apple.com -> Sécurité
#
# Puis lancer :  ./scripts/package-dmg.sh
# (override du profil : FLOWSCRIBE_NOTARY_PROFILE=autre ./scripts/package-dmg.sh)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROFILE="${FLOWSCRIBE_NOTARY_PROFILE:-flowscribe-notary}"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/Build/Products/Release/FlowScribe.app"
DMG="$ROOT/FlowScribe.dmg"

echo "==> Génération du projet (XcodeGen)"
xcodegen generate

echo "==> Build Release (Developer ID, hardened runtime)"
xcodebuild -project FlowScribe.xcodeproj -scheme FlowScribe -configuration Release \
  -derivedDataPath "$BUILD_DIR" -destination 'platform=macOS' clean build

[ -d "$APP" ] || { echo "ERREUR : app introuvable à $APP"; exit 1; }

echo "==> Création du DMG"
rm -f "$DMG"
hdiutil create -volname "FlowScribe" -srcfolder "$APP" -ov -format UDZO "$DMG"

echo "==> Notarisation (profil keychain : $PROFILE)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "==> Agrafage (stapler)"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

echo "✅ DMG notarisé prêt : $DMG"

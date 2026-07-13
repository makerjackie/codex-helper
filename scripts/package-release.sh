#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="${VERSION:-0.5.0}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
BUILD_DIR="$ROOT/.build/notarized"
APP_PATH="$BUILD_DIR/Codex Helper.app"
ZIP_PATH="$BUILD_DIR/Codex-Helper-$VERSION.zip"
DMG_PATH="$DIST_DIR/Codex-Helper-$VERSION.dmg"
SIGNING_IDENTITY="${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to a Developer ID Application identity}"
NOTARY_PROFILE="${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

SIGNING_IDENTITY="$SIGNING_IDENTITY" VERSION="$VERSION" OUTPUT_DIR="$BUILD_DIR" "$ROOT/scripts/build.sh"

ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"

DMG_STAGE="$BUILD_DIR/dmg"
mkdir -p "$DMG_STAGE"
ditto "$APP_PATH" "$DMG_STAGE/Codex Helper.app"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "Codex Helper" -srcfolder "$DMG_STAGE" -ov -format UDZO "$DMG_PATH"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"

(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$DMG_PATH")" > "$(basename "$DMG_PATH").sha256"
)
echo "$DMG_PATH"

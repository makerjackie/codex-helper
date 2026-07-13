#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/.build/release}"
APP_PATH="$OUTPUT_DIR/Codex Helper.app"
EXECUTABLE="$APP_PATH/Contents/MacOS/CodexHelper"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
ARCH_BUILD_DIR="$OUTPUT_DIR/architectures"
VERSION="${VERSION:-$(plutil -extract CFBundleShortVersionString raw "$ROOT/Resources/Info.plist")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(plutil -extract CFBundleVersion raw "$ROOT/Resources/Info.plist")}"

rm -rf "$APP_PATH" "$ARCH_BUILD_DIR"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$ARCH_BUILD_DIR"

for architecture in arm64 x86_64; do
  xcrun swiftc -O -whole-module-optimization \
    -target "$architecture-apple-macosx13.0" \
    "$ROOT"/Sources/*.swift \
    -framework AppKit \
    -framework ApplicationServices \
    -framework ServiceManagement \
    -o "$ARCH_BUILD_DIR/CodexHelper-$architecture"
done

lipo -create \
  "$ARCH_BUILD_DIR/CodexHelper-arm64" \
  "$ARCH_BUILD_DIR/CodexHelper-x86_64" \
  -output "$EXECUTABLE"

install -m 644 "$ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
install -m 644 "$ROOT/Resources/AppIcon.icns" "$APP_PATH/Contents/Resources/AppIcon.icns"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_PATH/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP_PATH/Contents/Info.plist"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_PATH"
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_PATH"
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "$APP_PATH"

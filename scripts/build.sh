#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/.build/release}"
APP_PATH="$OUTPUT_DIR/Codex Helper.app"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
XCODE_BUILD_DIR="$OUTPUT_DIR/xcode"
VERSION="${VERSION:-$(plutil -extract CFBundleShortVersionString raw "$ROOT/Resources/Info.plist")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(plutil -extract CFBundleVersion raw "$ROOT/Resources/Info.plist")}"

rm -rf "$APP_PATH" "$XCODE_BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

xcodebuild \
  -quiet \
  -project "$ROOT/CodexHelper.xcodeproj" \
  -scheme CodexHelper \
  -configuration Release \
  -derivedDataPath "$XCODE_BUILD_DIR" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  build

ditto "$XCODE_BUILD_DIR/Build/Products/Release/CodexHelper.app" "$APP_PATH"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_PATH/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP_PATH/Contents/Info.plist"

WIDGET_PATH="$APP_PATH/Contents/PlugIns/CodexHelperWidget.appex"
test -d "$WIDGET_PATH"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --sign - \
    --entitlements "$ROOT/WidgetExtension/CodexHelperWidget.entitlements" \
    "$WIDGET_PATH"
  codesign --force --sign - \
    --entitlements "$ROOT/Resources/CodexHelper.entitlements" \
    "$APP_PATH"
else
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" \
    --entitlements "$ROOT/WidgetExtension/CodexHelperWidget.entitlements" \
    "$WIDGET_PATH"
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" \
    --entitlements "$ROOT/Resources/CodexHelper.entitlements" \
    "$APP_PATH"
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
test "$(lipo -archs "$APP_PATH/Contents/MacOS/CodexHelper")" = "x86_64 arm64" \
  -o "$(lipo -archs "$APP_PATH/Contents/MacOS/CodexHelper")" = "arm64 x86_64"
echo "$APP_PATH"

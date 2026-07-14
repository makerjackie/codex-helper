#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
BUILD_DIR="$ROOT/.build"
ARCHITECTURE="$(uname -m)"

mkdir -p "$BUILD_DIR"
xcrun swiftc -warnings-as-errors \
  -target "$ARCHITECTURE-apple-macosx13.0" \
  "$ROOT"/Sources/*.swift \
  -framework AppKit \
  -framework SwiftUI \
  -framework ApplicationServices \
  -framework ServiceManagement \
  -framework WidgetKit \
  -o "$BUILD_DIR/CodexHelper"

CODEX_HELPER_DISABLE_ACCESSIBILITY_PROMPTS=1 "$BUILD_DIR/CodexHelper" --self-test
xcodebuild \
  -project "$ROOT/CodexHelper.xcodeproj" \
  -scheme CodexHelper \
  -configuration Debug \
  -derivedDataPath "$BUILD_DIR/xcode-test" \
  CODE_SIGNING_ALLOWED=NO \
  build >/dev/null
plutil -lint "$ROOT/Resources/Info.plist"
plutil -lint "$ROOT/Resources/CodexHelper.entitlements"
plutil -lint "$ROOT/WidgetExtension/Info.plist"
plutil -lint "$ROOT/WidgetExtension/CodexHelperWidget.entitlements"
ruby -rjson -e 'JSON.parse(File.read(ARGV.fetch(0)))' "$ROOT/Resources/config.json"
zsh -n "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/test.sh" "$ROOT/scripts/build.sh" "$ROOT/scripts/generate-project.sh" "$ROOT/scripts/package-release.sh"

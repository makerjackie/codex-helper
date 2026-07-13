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
  -framework ApplicationServices \
  -framework ServiceManagement \
  -o "$BUILD_DIR/CodexHelper"

"$BUILD_DIR/CodexHelper" --self-test
plutil -lint "$ROOT/Resources/Info.plist"
ruby -rjson -e 'JSON.parse(File.read(ARGV.fetch(0)))' "$ROOT/Resources/config.json"
zsh -n "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/test.sh" "$ROOT/scripts/build.sh" "$ROOT/scripts/package-release.sh"

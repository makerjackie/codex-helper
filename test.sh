#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
BUILD_DIR="$ROOT/.build"

mkdir -p "$BUILD_DIR"
xcrun swiftc -warnings-as-errors "$ROOT/Sources/main.swift" \
  -framework AppKit \
  -framework ApplicationServices \
  -o "$BUILD_DIR/CodexAutoRetry"

"$BUILD_DIR/CodexAutoRetry" --self-test
plutil -lint "$ROOT/Resources/Info.plist"
plutil -lint "$ROOT/Resources/com.makerjackie.codex-auto-retry.plist"
ruby -rjson -e 'JSON.parse(File.read(ARGV.fetch(0)))' "$ROOT/Resources/config.json"
zsh -n "$ROOT/install.sh" "$ROOT/uninstall.sh" "$ROOT/test.sh"

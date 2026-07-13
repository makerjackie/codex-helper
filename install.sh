#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
APP_NAME="Codex Auto Retry.app"
APP_PATH="$HOME/Applications/$APP_NAME"
EXECUTABLE="$APP_PATH/Contents/MacOS/CodexAutoRetry"
SUPPORT_DIR="$HOME/Library/Application Support/CodexAutoRetry"
PLIST_PATH="$HOME/Library/LaunchAgents/com.makerjackie.codex-auto-retry.plist"
BUILD_DIR="$ROOT/.build"

mkdir -p "$BUILD_DIR" "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$SUPPORT_DIR" "$HOME/Library/LaunchAgents"

xcrun swiftc -O "$ROOT/Sources/main.swift" \
  -framework AppKit \
  -framework ApplicationServices \
  -o "$BUILD_DIR/CodexAutoRetry"

install -m 755 "$BUILD_DIR/CodexAutoRetry" "$EXECUTABLE"
install -m 644 "$ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
if [[ ! -f "$SUPPORT_DIR/config.json" ]]; then
  install -m 644 "$ROOT/Resources/config.json" "$SUPPORT_DIR/config.json"
fi
codesign --force --deep --sign - "$APP_PATH"

sed \
  -e "s|__EXECUTABLE__|$EXECUTABLE|g" \
  -e "s|__LOG_DIR__|$SUPPORT_DIR|g" \
  "$ROOT/Resources/com.makerjackie.codex-auto-retry.plist" > "$PLIST_PATH"
plutil -lint "$PLIST_PATH"

launchctl bootout "gui/$UID/com.makerjackie.codex-auto-retry" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$PLIST_PATH"
launchctl kickstart -k "gui/$UID/com.makerjackie.codex-auto-retry"

"$EXECUTABLE" --self-test

echo "Installed: $APP_PATH"
echo "Log: $SUPPORT_DIR/agent.log"
echo "Language: edit $SUPPORT_DIR/config.json (auto, en, or zh)"

#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}"
APP_NAME="Codex Helper.app"
APP_PATH="$HOME/Applications/$APP_NAME"
EXECUTABLE="$APP_PATH/Contents/MacOS/CodexHelper"
SUPPORT_DIR="$HOME/Library/Application Support/CodexHelper"

launchctl bootout "gui/$UID/com.makerjackie.codex-auto-retry" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/com.makerjackie.codex-auto-retry.plist"
rm -rf "$HOME/Applications/Codex Auto Retry.app"

SIGNING_IDENTITY="-" OUTPUT_DIR="$ROOT/.build/install" "$ROOT/scripts/build.sh"

rm -rf "$APP_PATH"
mkdir -p "$HOME/Applications" "$SUPPORT_DIR"
ditto "$ROOT/.build/install/$APP_NAME" "$APP_PATH"
if [[ ! -f "$SUPPORT_DIR/config.json" ]]; then
  install -m 644 "$ROOT/Resources/config.json" "$SUPPORT_DIR/config.json"
fi

"$EXECUTABLE" --self-test
open "$APP_PATH"

echo "Installed: $APP_PATH"
echo "Log: $SUPPORT_DIR/agent.log"
echo "Use the menu bar icon or open Codex Helper from Spotlight to change settings."

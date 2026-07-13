#!/bin/zsh
set -euo pipefail

LABEL="com.makerjackie.codex-auto-retry"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
rm -f "$PLIST_PATH"
rm -rf "$HOME/Applications/Codex Auto Retry.app"

echo "Uninstalled Codex Auto Retry. Runtime logs/state remain in:"
echo "$HOME/Library/Application Support/CodexAutoRetry"

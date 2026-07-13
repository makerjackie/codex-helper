#!/bin/zsh
set -euo pipefail

OLD_LABEL="com.makerjackie.codex-auto-retry"

pkill -x CodexHelper 2>/dev/null || true
launchctl bootout "gui/$UID/$OLD_LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$OLD_LABEL.plist"
rm -rf "$HOME/Applications/Codex Auto Retry.app"
rm -rf "$HOME/Applications/Codex Helper.app"

echo "Uninstalled Codex Helper. Runtime logs/state remain in:"
echo "$HOME/Library/Application Support/CodexHelper"

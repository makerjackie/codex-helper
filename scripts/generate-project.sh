#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required: brew install xcodegen" >&2
  exit 1
fi

cd "$ROOT"
xcodegen generate --spec project.yml

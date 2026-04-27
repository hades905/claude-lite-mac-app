#!/bin/zsh
set -euo pipefail

SCRIPT_PATH="${0:A}"
SCRIPT_DIR="${SCRIPT_PATH:h}"
PROJECT_DIR="$SCRIPT_DIR"

if [[ ! -f "$PROJECT_DIR/Package.swift" ]]; then
  osascript -e 'display alert "Claude Lite Latest" message "Cannot find Package.swift next to this launcher. Keep this file in the claude-lite-mac-app folder."'
  exit 1
fi

echo "Opening Claude Lite from the latest source..."
echo "Project: $PROJECT_DIR"
echo

cd "$PROJECT_DIR"

if pgrep -f "$PROJECT_DIR/dist/.*\\.app/Contents/MacOS/" >/dev/null 2>&1; then
  pkill -f "$PROJECT_DIR/dist/.*\\.app/Contents/MacOS/" || true
fi

"$PROJECT_DIR/scripts/package-app.sh"

APP_PATH="$(find "$PROJECT_DIR/dist" -maxdepth 1 -name '*.app' -print -quit)"
if [[ -z "$APP_PATH" ]]; then
  osascript -e 'display alert "Claude Lite Latest" message "The app was built, but no .app bundle was found in dist."'
  exit 1
fi

open "$APP_PATH"

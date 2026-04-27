#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ICON_PATH="$ROOT_DIR/.build-support/packaging/AppIcon.icns"
OUTPUT_DIR="$ROOT_DIR/dist"
BOOTSTRAP_CONFIG_PATH="$ROOT_DIR/.local/tuzi-config.json"

cd "$ROOT_DIR"

swift build -c release --product ClaudeLiteMacApp
swift build -c release --product ClaudeLitePackager
RELEASE_DIR="$(swift build -c release --show-bin-path)"
EXECUTABLE_PATH="$RELEASE_DIR/ClaudeLiteMacApp"
swift scripts/generate-icon.swift

PACKAGER_ARGS=(
  --executable "$EXECUTABLE_PATH"
  --icon "$ICON_PATH"
  --output-dir "$OUTPUT_DIR"
)

if [[ -f "$BOOTSTRAP_CONFIG_PATH" ]]; then
  PACKAGER_ARGS+=(--bootstrap-config "$BOOTSTRAP_CONFIG_PATH")
fi

swift run -c release ClaudeLitePackager "${PACKAGER_ARGS[@]}"

#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ICON_PATH="$ROOT_DIR/Assets/AppIcon.icns"
OUTPUT_DIR="$ROOT_DIR/dist"

cd "$ROOT_DIR"

swift build -c release --product ClaudeLiteMacApp
swift build -c release --product ClaudeLitePackager
RELEASE_DIR="$(swift build -c release --show-bin-path)"
EXECUTABLE_PATH="$RELEASE_DIR/ClaudeLiteMacApp"

if [[ ! -f "$ICON_PATH" ]]; then
  swift scripts/generate-icon.swift
  mkdir -p "$ROOT_DIR/Assets"
  cp "$ROOT_DIR/.build-support/packaging/AppIcon.icns" "$ICON_PATH"
fi

PACKAGER_ARGS=(
  --executable "$EXECUTABLE_PATH"
  --icon "$ICON_PATH"
  --output-dir "$OUTPUT_DIR"
)

swift run -c release ClaudeLitePackager "${PACKAGER_ARGS[@]}"

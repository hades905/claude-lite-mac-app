#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ICON_PATH="$ROOT_DIR/.build-support/packaging/AppIcon.icns"
OUTPUT_DIR="$ROOT_DIR/dist"

cd "$ROOT_DIR"

swift build -c release --product ClaudeLiteMacApp
swift build -c release --product ClaudeLitePackager
RELEASE_DIR="$(swift build -c release --show-bin-path)"
EXECUTABLE_PATH="$RELEASE_DIR/ClaudeLiteMacApp"
swift scripts/generate-icon.swift

swift run -c release ClaudeLitePackager \
  --executable "$EXECUTABLE_PATH" \
  --icon "$ICON_PATH" \
  --output-dir "$OUTPUT_DIR"

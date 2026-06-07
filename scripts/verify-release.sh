#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT_DIR/dist/问.app"
MAX_APP_BYTES=$((100 * 1024 * 1024))

cd "$ROOT_DIR"

echo "== Offline smoke =="
swift run ClaudeLiteSmoke

echo "== Tests =="
swift test

echo "== Package =="
"$ROOT_DIR/scripts/package-app.sh"

echo "== App size =="
if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing packaged app: $APP_PATH" >&2
  exit 1
fi

APP_BYTES="$(du -sk "$APP_PATH" | awk '{print $1 * 1024}')"
echo "app_bytes=$APP_BYTES"
if (( APP_BYTES > MAX_APP_BYTES )); then
  echo "Packaged app exceeds 100 MB limit." >&2
  exit 1
fi

echo "== Bundled config check =="
if find "$APP_PATH" -path '*/.local/*' -o -name 'tuzi-config.json' -print | grep -q .; then
  echo "Packaged app contains local config material." >&2
  exit 1
fi

echo "== Secret scan =="
if rg --pcre2 -n --hidden \
  --glob '!/.git/**' \
  --glob '!/.build/**' \
  --glob '!dist/**' \
  --glob '!Package.resolved' \
  --glob '!Sources/ClaudeLiteCore/Rendering/Resources/marked.min.js' \
  --glob '!Sources/ClaudeLiteCore/Rendering/Resources/tex-svg.js' \
  '(sk-[A-Za-z0-9_-]{12,}|Bearer [A-Za-z0-9._-]{12,}|modelApiKey"\s*:\s*"(?!YOUR_|test-|model-key|bootstrap-|private-)|modelAPIKey"\s*:\s*"(?!YOUR_|test-|model-key|bootstrap-|private-)|userApiKey"\s*:\s*"(?!YOUR_|test-|user-key|bootstrap-|private-)|userAPIKey"\s*:\s*"(?!YOUR_|test-|user-key|bootstrap-|private-))' \
  .; then
  echo "Potential secret found." >&2
  exit 1
fi

echo "verify_release=passed"

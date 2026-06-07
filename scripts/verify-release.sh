#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_PATH="$ROOT_DIR/dist/问.app"
MAX_APP_BYTES=$((100 * 1024 * 1024))
MAX_SMOKE_START_MS=5000
MAX_SMOKE_SEND_MS=5000
MAX_SMOKE_RSS_MB=100

cleanup_build_cache() {
  rm -rf "$ROOT_DIR/.build"
  rm -rf "$ROOT_DIR/.build-support"
  rm -rf "$ROOT_DIR/.build-verification"
  rm -rf "$ROOT_DIR/.swiftpm"
  rm -rf "$ROOT_DIR/DerivedData"
}

metric_value() {
  local name="$1"
  echo "$SMOKE_OUTPUT" | awk -F= -v key="$name" '$1 == key { print $2; exit }'
}

assert_metric_under_limit() {
  local name="$1"
  local limit="$2"
  local value
  value="$(metric_value "$name")"

  if [[ -z "$value" ]]; then
    echo "Smoke output missing metric: $name" >&2
    exit 1
  fi

  if (( value > limit )); then
    echo "Smoke metric $name=$value exceeds limit $limit." >&2
    exit 1
  fi
}

trap cleanup_build_cache EXIT

cd "$ROOT_DIR"

echo "== Offline smoke =="
SMOKE_OUTPUT="$(swift run ClaudeLiteSmoke)"
echo "$SMOKE_OUTPUT"
assert_metric_under_limit "start_ms" "$MAX_SMOKE_START_MS"
assert_metric_under_limit "send_ms" "$MAX_SMOKE_SEND_MS"
assert_metric_under_limit "rss_mb" "$MAX_SMOKE_RSS_MB"

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

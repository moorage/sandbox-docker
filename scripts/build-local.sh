#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_NAME="$(basename "$ROOT_DIR")"
IMAGE_NAME="codex-cli:local"
CACHE_FILE="$ROOT_DIR/.build-cachebust"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not installed or not in PATH" >&2
  exit 1
fi

# Remove the previous local tag and any image tagged with the repo directory name.
for tag in "$IMAGE_NAME" "$PROJECT_NAME"; do
  if docker image inspect "$tag" >/dev/null 2>&1; then
    docker image rm -f "$tag"
  fi
done

apt_cachebust=1
npm_cachebust=1
if [ -f "$CACHE_FILE" ]; then
  IFS=' ' read -r apt_cachebust npm_cachebust < "$CACHE_FILE" || true
fi
apt_cachebust=$((apt_cachebust + 1))
npm_cachebust=$((npm_cachebust + 1))
printf "%s %s\n" "$apt_cachebust" "$npm_cachebust" > "$CACHE_FILE"

# Build fresh.
cd "$ROOT_DIR"
docker build \
  --build-arg APT_CACHEBUST="$apt_cachebust" \
  --build-arg NPM_CACHEBUST="$npm_cachebust" \
  -t "$IMAGE_NAME" \
  .

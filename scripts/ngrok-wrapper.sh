#!/usr/bin/env bash
set -euo pipefail

ngrok_home="${NGROK_HOME:-/tmp/ngrok-home}"
ngrok_config_home="$ngrok_home/.config"
ngrok_cache_home="${NGROK_CACHE_HOME:-/tmp/ngrok-cache}"
ngrok_config_dir="$ngrok_config_home/ngrok"

for arg in "$@"; do
  case "$arg" in
    --config|--config=*)
      exec /usr/local/bin/ngrok-real "$@"
      ;;
  esac
done

if ! mkdir -p "$ngrok_config_dir"; then
  echo "warning: failed to create ngrok config dir at $ngrok_config_dir" >&2
fi
mkdir -p "$ngrok_cache_home"

export HOME=/tmp
export XDG_CONFIG_HOME="$ngrok_config_home"
export XDG_CACHE_HOME="$ngrok_cache_home"

exec /usr/local/bin/ngrok-real "$@"

#!/usr/bin/env bash
set -euo pipefail

if [ -z "${DISPLAY:-}" ]; then
  export DISPLAY=:99
fi

# Some tooling (Chromium, crashpad, etc.) expects a writable XDG runtime dir.
# In this image the root FS may be read-only, so ensure it lives under /tmp.
if [ -z "${XDG_RUNTIME_DIR:-}" ]; then
  export XDG_RUNTIME_DIR=/tmp/xdg-runtime
fi
if [ ! -d "$XDG_RUNTIME_DIR" ]; then
  if ! mkdir -p "$XDG_RUNTIME_DIR"; then
    echo "warning: failed to create XDG_RUNTIME_DIR at $XDG_RUNTIME_DIR" >&2
  fi
fi
if [ -d "$XDG_RUNTIME_DIR" ]; then
  if ! chmod 700 "$XDG_RUNTIME_DIR"; then
    echo "warning: failed to chmod XDG_RUNTIME_DIR at $XDG_RUNTIME_DIR" >&2
  fi
fi

if [ "${CODEX_DISABLE_XVFB:-}" != "1" ]; then
  if command -v Xvfb >/dev/null 2>&1; then
    Xvfb "$DISPLAY" -screen 0 "${XVFB_SCREEN:-1920x1080x24}" -nolisten tcp -ac >/tmp/xvfb.log 2>&1 &
    xvfb_pid=$!
    sleep 0.2
    if ! kill -0 "$xvfb_pid" 2>/dev/null; then
      echo "warning: Xvfb failed to start on $DISPLAY (see /tmp/xvfb.log)" >&2
    fi
  else
    echo "warning: Xvfb not found; DISPLAY is set but no X server is running" >&2
  fi
fi

exec codex "$@"

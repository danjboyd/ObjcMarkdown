#!/usr/bin/env bash
# Runs before the AppImage packaging job (gnustep-packager's
# preflight-command), in the CI image (ci/linux/Dockerfile): checks the
# toolchain and starts a display for the smoke test, which opens the app.
# The Adwaita theme is fetched and built by stage-linux-runtime.sh from its
# pin in packaging/inputs.json.
set -euo pipefail

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $name" >&2
    exit 1
  fi
}

test -f /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
require_command git
require_command clang
require_command gmake
require_command pandoc
require_command pwsh
require_command python3

if [[ -z "${DISPLAY:-}" ]]; then
  require_command Xvfb
  display=":99"
  setsid Xvfb "$display" -screen 0 1600x1000x24 -nolisten tcp >/tmp/xvfb.log 2>&1 < /dev/null &
  for _ in $(seq 1 50); do
    [[ -e "/tmp/.X11-unix/X${display#:}" ]] && break
    sleep 0.1
  done
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "DISPLAY=$display" >> "$GITHUB_ENV"
  fi
  echo "Started Xvfb on $display"
fi

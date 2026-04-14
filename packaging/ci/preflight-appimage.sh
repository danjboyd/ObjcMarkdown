#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
THEME_DIR="$ROOT/third_party/plugins-themes-Adwaita"
THEME_URL="https://github.com/danjboyd/plugins-themes-Adwaita.git"
THEME_REF="9d455f67587242400f6620a0e8884084850d1204"

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

mkdir -p "$ROOT/third_party"
if [[ ! -d "$THEME_DIR/.git" ]]; then
  rm -rf "$THEME_DIR"
  git clone --filter=blob:none "$THEME_URL" "$THEME_DIR"
fi

git -C "$THEME_DIR" fetch --depth 1 origin "$THEME_REF"
git -C "$THEME_DIR" checkout --force "$THEME_REF"

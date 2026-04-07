#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GNUSTEP_SH="${GNUSTEP_SH:-/clang64/share/GNUstep/Makefiles/GNUstep.sh}"

# Desktop action helper: allow explicit "new window" launches without
# passing an unknown option through to the app.
if [[ "${1:-}" == "--new-window" ]]; then
  shift
fi

if [[ ! -f "$GNUSTEP_SH" ]]; then
  echo "GNUstep.sh not found at: $GNUSTEP_SH" >&2
  echo "Set GNUSTEP_SH to your MSYS2 GNUstep.sh path and retry." >&2
  exit 1
fi

# GNUstep.sh expects some possibly-unset variables.
set +u
. "$GNUSTEP_SH"
set -u

MAKE_TOOL="${MAKE_TOOL:-gmake}"
if ! command -v "$MAKE_TOOL" >/dev/null 2>&1; then
  MAKE_TOOL=make
fi

"$MAKE_TOOL" -C "$ROOT/third_party/libs-OpenSave" Source
"$MAKE_TOOL" -C "$ROOT/third_party/TextViewVimKitBuild"
"$MAKE_TOOL" -C "$ROOT" ObjcMarkdown ObjcMarkdownViewer

RUNTIME_PATHS="$ROOT/ObjcMarkdown/obj:$ROOT/third_party/libs-OpenSave/Source/obj:$ROOT/third_party/TextViewVimKitBuild/obj"
PATH="$RUNTIME_PATHS:$PATH"
export PATH

if [[ -z "${GSTheme:-}" ]]; then
  if [[ "${OMD_USE_SOMBRE_THEME:-0}" == "1" ]]; then
    export GSTheme=Sombre
  else
    # Sombre is unstable on Windows GNUstep; prefer WinUI when available and
    # fall back to WinUX on plain CLANG64 runtimes that do not include it.
    if [[ -f "$HOME/GNUstep/Library/Themes/WinUITheme.theme/WinUITheme.dll" || \
          -f "/clang64/lib/GNUstep/Themes/WinUITheme.theme/WinUITheme.dll" ]]; then
      export GSTheme=WinUITheme
    else
      export GSTheme=WinUXTheme
    fi
  fi
fi

openapp "$ROOT/ObjcMarkdownViewer/MarkdownViewer.app" "$@"

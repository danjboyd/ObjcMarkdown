#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GNUSTEP_SH="${GNUSTEP_SH:-/clang64/share/GNUstep/Makefiles/GNUstep.sh}"

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

if [[ "${OMD_USE_SOMBRE_THEME:-1}" == "1" && -z "${GSTheme:-}" ]]; then
  export GSTheme=Sombre
fi

openapp "$ROOT/ObjcMarkdownViewer/ObjcMarkdownViewer.app" "$@"

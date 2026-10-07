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

# The top-level build covers every library the app links (libs-OpenSave,
# TextViewVimKit, the GPUpdater libraries, ObjcMarkdown) and the app.
# A failed build doesn't stop the launch: on Windows a running viewer
# locks its DLLs, so relinking fails until it quits; the last build runs.
APP="$ROOT/ObjcMarkdownViewer/MarkdownViewer.app"
if ! "$MAKE_TOOL" -C "$ROOT" OMD_SKIP_TESTS=1; then
  if [[ ! -d "$APP" ]]; then
    echo "omd-viewer: the build failed and there is no earlier build to run" >&2
    exit 1
  fi
  echo "omd-viewer: the build failed (a running MarkdownViewer locks its DLLs); starting the last build" >&2
fi

# Windows finds the app's DLLs on PATH: one directory per library above.
RUNTIME_PATHS="$ROOT/ObjcMarkdown/obj:$ROOT/third_party/libs-OpenSave/Source/obj:$ROOT/third_party/TextViewVimKitBuild/obj"
RUNTIME_PATHS="$RUNTIME_PATHS:$ROOT/third_party/GPUpdaterCore/obj:$ROOT/third_party/GPUpdaterUI/obj"
PATH="$RUNTIME_PATHS:$PATH"
export PATH

# The theme is the GSTheme default (Preferences, or GNUstep's own); pass
# -GSTheme <Name> to try another for one launch.
openapp "$APP" "$@"

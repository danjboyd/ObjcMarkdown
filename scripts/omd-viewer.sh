#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Desktop action helper: allow explicit "new window" launches without
# passing an unknown option through to the app.
if [[ "${1:-}" == "--new-window" ]]; then
  shift
fi

# GNUstep.sh assumes unset vars may be read; disable nounset while sourcing.
set +u
. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

gmake -C "$ROOT/third_party/libs-OpenSave" Source
gmake -C "$ROOT" ObjcMarkdown ObjcMarkdownViewer

APP_BIN="$ROOT/ObjcMarkdownViewer/MarkdownViewer.app/MarkdownViewer"
LD_LIBRARY_PATH="$ROOT/ObjcMarkdown/obj:$ROOT/third_party/libs-OpenSave/Source/obj:/usr/GNUstep/System/Library/Libraries${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
exec "$APP_BIN" "$@"

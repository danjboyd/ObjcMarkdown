#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESKTOP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
TEMPLATE="$ROOT/Resources/MarkdownViewer.desktop.in"
OUT="$DESKTOP_DIR/markdownviewer.desktop"
EXEC_PATH="$ROOT/scripts/omd-viewer.sh"
ICON_PATH="$ROOT/Resources/markdown_icon.png"
LEGACY_ENTRIES=(
  "$DESKTOP_DIR/objcmarkdownviewer.desktop"
  "$DESKTOP_DIR/objcmd-markdown-viewer-dev.desktop"
)

mkdir -p "$DESKTOP_DIR"
chmod +x "$EXEC_PATH"
sed -e "s|@EXEC@|$EXEC_PATH|g" -e "s|@ICON@|$ICON_PATH|g" "$TEMPLATE" > "$OUT"

for legacy in "${LEGACY_ENTRIES[@]}"; do
  if [[ -f "$legacy" ]] && grep -Fq "$ROOT" "$legacy"; then
    rm -f "$legacy"
  fi
done

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
fi

echo "Installed: $OUT"

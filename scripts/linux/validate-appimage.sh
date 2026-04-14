#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-}"
EXTRACT_DIR=""
INSPECT_ROOT=""
APP_ROOT=""
RUNTIME_ROOT=""

if [[ -z "$TARGET" ]]; then
  echo "usage: $0 <AppImage-or-extracted-root>" >&2
  exit 1
fi

cleanup() {
  if [[ -n "$EXTRACT_DIR" && -d "$EXTRACT_DIR" ]]; then
    rm -rf "$EXTRACT_DIR"
  fi
}

trap cleanup EXIT

if [[ -d "$TARGET" ]]; then
  INSPECT_ROOT="$(cd "$TARGET" && pwd)"
elif [[ -f "$TARGET" ]]; then
  TARGET="$(cd "$(dirname "$TARGET")" && pwd)/$(basename "$TARGET")"
  chmod +x "$TARGET"
  EXTRACT_DIR="$(mktemp -d)"
  (
    cd "$EXTRACT_DIR"
    "$TARGET" --appimage-extract >/dev/null
  )
  INSPECT_ROOT="$EXTRACT_DIR/squashfs-root"
else
  echo "ERROR: target not found: $TARGET" >&2
  exit 1
fi

APP_ROOT="$INSPECT_ROOT/usr/app"
RUNTIME_ROOT="$INSPECT_ROOT/usr/runtime"
APP_BINARY="$APP_ROOT/MarkdownViewer.app/MarkdownViewer"
APP_LIB_DIR="$APP_ROOT/lib"
GNUSTEP_LIB_DIR="$RUNTIME_ROOT/System/Library/Libraries"
RUNTIME_LIB_DIR="$RUNTIME_ROOT/lib"
DEFAULTS_TOOL="$RUNTIME_ROOT/System/Tools/defaults"
THEME_BUNDLE="$RUNTIME_ROOT/System/Library/Themes/Adwaita.theme"
PANDOC_PATH="$RUNTIME_ROOT/bin/pandoc"
PANDOC_DATA_DIR="$RUNTIME_ROOT/share/pandoc"
DESKTOP_FILE="$INSPECT_ROOT/usr/share/applications/objcmarkdown.desktop"
ICON_FILE="$INSPECT_ROOT/usr/share/icons/hicolor/256x256/apps/objcmarkdown.png"
BACKEND_BUNDLE="$(find "$RUNTIME_ROOT/System/Library/Bundles" -maxdepth 2 -type f -name 'libgnustep-back-*' | head -n 1 || true)"
LIBRARY_PATH="$APP_LIB_DIR:$GNUSTEP_LIB_DIR:$RUNTIME_LIB_DIR"

require_path() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "ERROR: required packaged path missing: $path" >&2
    exit 1
  fi
}

inspect_runpath() {
  local binary="$1"
  local runpath=""
  local entry=""

  runpath="$(readelf -d "$binary" 2>/dev/null | awk -F'[][]' '/(RUNPATH|RPATH)/ { print $2; exit }')"
  if [[ -z "$runpath" ]]; then
    return 0
  fi

  IFS=':' read -r -a entries <<<"$runpath"
  for entry in "${entries[@]}"; do
    if [[ -z "$entry" ]]; then
      continue
    fi
    case "$entry" in
      '$ORIGIN'*|"$INSPECT_ROOT"/*)
        ;;
      *)
        echo "ERROR: packaged ELF escaped the AppImage via RUNPATH/RPATH: $binary -> $entry" >&2
        exit 1
        ;;
    esac
  done
}

inspect_ldd_resolves() {
  local binary="$1"
  local output=""

  output="$(env LD_LIBRARY_PATH="$LIBRARY_PATH" ldd "$binary" 2>/dev/null || true)"
  if grep -Fq "=> not found" <<<"$output"; then
    echo "ERROR: packaged ELF has unresolved dependencies under packaged LD_LIBRARY_PATH: $binary" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

verify_bundled_pandoc_conversion() {
  local scratch_dir=""
  local markdown_path=""
  local output_path=""
  local log_path=""

  scratch_dir="$(mktemp -d)"
  markdown_path="$scratch_dir/validate-pandoc.md"
  output_path="$scratch_dir/validate-pandoc.docx"
  log_path="$scratch_dir/pandoc.log"

  printf '# Validate\n\nBundled pandoc conversion smoke test.\n' >"$markdown_path"
  if ! env \
    LD_LIBRARY_PATH="$LIBRARY_PATH" \
    PANDOC_DATA_DIR="$PANDOC_DATA_DIR" \
    "$PANDOC_PATH" \
      --data-dir "$PANDOC_DATA_DIR" \
      "$markdown_path" \
      --output "$output_path" >"$log_path" 2>&1; then
    echo "ERROR: bundled pandoc failed DOCX conversion smoke test" >&2
    cat "$log_path" >&2 || true
    rm -rf "$scratch_dir"
    exit 1
  fi

  if [[ ! -s "$output_path" ]]; then
    echo "ERROR: bundled pandoc did not produce DOCX output" >&2
    cat "$log_path" >&2 || true
    rm -rf "$scratch_dir"
    exit 1
  fi

  rm -rf "$scratch_dir"
}

require_path "$INSPECT_ROOT/AppRun"
require_path "$APP_BINARY"
require_path "$APP_LIB_DIR"
require_path "$DEFAULTS_TOOL"
require_path "$THEME_BUNDLE"
require_path "$PANDOC_PATH"
require_path "$PANDOC_DATA_DIR"
require_path "$DESKTOP_FILE"
require_path "$ICON_FILE"

if [[ -z "$BACKEND_BUNDLE" || ! -f "$BACKEND_BUNDLE" ]]; then
  echo "ERROR: GNUstep backend bundle missing under $RUNTIME_ROOT/System/Library/Bundles" >&2
  exit 1
fi

for required_image in \
  "$RUNTIME_ROOT/System/Library/Images/GNUstepMenuImage.tiff" \
  "$RUNTIME_ROOT/System/Library/Images/common_ArrowRight.tiff" \
  "$RUNTIME_ROOT/System/Library/Images/common_SwitchOn.tiff" \
  "$RUNTIME_ROOT/System/Library/Images/common_SwitchOff.tiff"; do
  require_path "$required_image"
done

while IFS= read -r -d '' file; do
  if readelf -h "$file" >/dev/null 2>&1; then
    inspect_runpath "$file"
    inspect_ldd_resolves "$file"
  fi
done < <(find "$APP_ROOT" "$RUNTIME_ROOT" -type f -print0)

verify_bundled_pandoc_conversion

printf 'APP_ROOT=%s\n' "$APP_ROOT"
printf 'RUNTIME_ROOT=%s\n' "$RUNTIME_ROOT"
printf 'APP_BINARY=%s\n' "$APP_BINARY"
printf 'DEFAULTS_TOOL=%s\n' "$DEFAULTS_TOOL"
printf 'THEME_BUNDLE=%s\n' "$THEME_BUNDLE"
printf 'BACKEND_BUNDLE=%s\n' "$BACKEND_BUNDLE"
printf 'PANDOC_PATH=%s\n' "$PANDOC_PATH"
printf 'PANDOC_DATA_DIR=%s\n' "$PANDOC_DATA_DIR"
printf 'DESKTOP_FILE=%s\n' "$DESKTOP_FILE"
printf 'ICON_FILE=%s\n' "$ICON_FILE"
printf 'LD_LIBRARY_PATH=%s\n' "$LIBRARY_PATH"

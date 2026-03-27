#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-}"
EXTRACT_DIR=""
INSPECT_ROOT=""

if [[ -z "$TARGET" ]]; then
  echo "usage: $0 <AppDir-or-AppImage>" >&2
  exit 1
fi

cleanup() {
  if [[ -n "$EXTRACT_DIR" && -d "$EXTRACT_DIR" ]]; then
    rm -rf "$EXTRACT_DIR"
  fi
}

trap cleanup EXIT

if [[ -d "$TARGET" ]]; then
  TARGET="$(cd "$TARGET" && pwd)"
  RUN_CMD=("$TARGET/AppRun" --omd-print-runtime-env)
  INSPECT_ROOT="$TARGET"
elif [[ -f "$TARGET" ]]; then
  TARGET="$(cd "$(dirname "$TARGET")" && pwd)/$(basename "$TARGET")"
  chmod +x "$TARGET"
  RUN_CMD=("$TARGET" --appimage-extract-and-run --omd-print-runtime-env)
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

OUTPUT="$("${RUN_CMD[@]}")"
printf '%s\n' "$OUTPUT"

expect_line() {
  local key="$1"
  local expected="$2"
  if ! grep -Fqx "$key=$expected" <<<"$OUTPUT"; then
    echo "ERROR: expected $key=$expected" >&2
    exit 1
  fi
}

expect_present_flag() {
  local key="$1"
  expect_line "$key" "1"
}

expect_contains() {
  local needle="$1"
  if ! grep -Fq "$needle" <<<"$OUTPUT"; then
    echo "ERROR: expected diagnostic output to contain: $needle" >&2
    exit 1
  fi
}

value_for() {
  local key="$1"
  awk -F= -v search_key="$key" '$1 == search_key { print substr($0, length(search_key) + 2) }' <<<"$OUTPUT" | head -n 1
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
        echo "ERROR: packaged ELF escaped the AppDir/AppImage via RUNPATH/RPATH: $binary -> $entry" >&2
        exit 1
        ;;
    esac
  done
}

inspect_ldd_resolves() {
  local binary="$1"
  local output=""

  output="$(env \
    LD_LIBRARY_PATH="$INSPECT_ROOT/usr/lib/ObjcMarkdownRuntime:$INSPECT_ROOT/usr/GNUstep/System/Library/Libraries:$INSPECT_ROOT/usr/lib" \
    ldd "$binary" 2>/dev/null || true)"
  if grep -Fq "=> not found" <<<"$output"; then
    echo "ERROR: packaged ELF has unresolved dependencies under packaged LD_LIBRARY_PATH: $binary" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

verify_bundled_pandoc_conversion() {
  local pandoc_path="$1"
  local pandoc_data_dir="$2"
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
    LD_LIBRARY_PATH="$INSPECT_ROOT/usr/lib/ObjcMarkdownRuntime:$INSPECT_ROOT/usr/GNUstep/System/Library/Libraries:$INSPECT_ROOT/usr/lib" \
    "$pandoc_path" \
      --data-dir "$pandoc_data_dir" \
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

expect_present_flag APP_BINARY_PRESENT
expect_present_flag DEFAULTS_TOOL_PRESENT
expect_present_flag THEME_BUNDLE_PRESENT
expect_present_flag BACKEND_BUNDLE_PRESENT
expect_present_flag PANDOC_PRESENT
expect_present_flag PANDOC_DATA_PRESENT
expect_line GSTheme Adwaita
expect_contains "GNUSTEP_SYSTEM_ROOT="
expect_contains "GNUSTEP_USER_ROOT="
expect_contains "GNUSTEP_PATHLIST="
expect_contains "GNUSTEP_SYSTEM_LIBRARY="
expect_contains "GNUSTEP_SYSTEM_LIBRARIES="
expect_contains "GNUSTEP_SYSTEM_TOOLS="
expect_contains "LD_LIBRARY_PATH="

APPDIR_PATH="$(value_for APPDIR)"
GNUSTEP_SYSTEM_ROOT_PATH="$(value_for GNUSTEP_SYSTEM_ROOT)"
GNUSTEP_SYSTEM_LIBRARY_PATH="$(value_for GNUSTEP_SYSTEM_LIBRARY)"
GNUSTEP_SYSTEM_LIBRARIES_PATH="$(value_for GNUSTEP_SYSTEM_LIBRARIES)"
GNUSTEP_SYSTEM_TOOLS_PATH="$(value_for GNUSTEP_SYSTEM_TOOLS)"
GNUSTEP_PATHLIST_VALUE="$(value_for GNUSTEP_PATHLIST)"
PANDOC_PATH_VALUE="$(value_for PANDOC_PATH)"
PANDOC_DATA_DIR_VALUE="$(value_for PANDOC_DATA_DIR)"

for required in \
  "$APPDIR_PATH" \
  "$GNUSTEP_SYSTEM_ROOT_PATH" \
  "$GNUSTEP_SYSTEM_LIBRARY_PATH" \
  "$GNUSTEP_SYSTEM_LIBRARIES_PATH" \
  "$GNUSTEP_SYSTEM_TOOLS_PATH" \
  "$PANDOC_PATH_VALUE" \
  "$PANDOC_DATA_DIR_VALUE"; do
  if [[ -z "$required" ]]; then
    echo "ERROR: missing expected diagnostic value" >&2
    exit 1
  fi
done

case "$GNUSTEP_SYSTEM_ROOT_PATH" in
  "$APPDIR_PATH"/*) ;;
  *)
    echo "ERROR: GNUSTEP_SYSTEM_ROOT escaped the packaged AppDir: $GNUSTEP_SYSTEM_ROOT_PATH" >&2
    exit 1
    ;;
esac

for path_value in \
  "$GNUSTEP_SYSTEM_LIBRARY_PATH" \
  "$GNUSTEP_SYSTEM_LIBRARIES_PATH" \
  "$GNUSTEP_SYSTEM_TOOLS_PATH" \
  "$PANDOC_PATH_VALUE" \
  "$PANDOC_DATA_DIR_VALUE"; do
  case "$path_value" in
    "$APPDIR_PATH"/*) ;;
    *)
      echo "ERROR: packaged GNUstep path escaped the AppDir: $path_value" >&2
      exit 1
      ;;
  esac
done

if [[ "$GNUSTEP_PATHLIST_VALUE" != *"$GNUSTEP_SYSTEM_ROOT_PATH"* ]]; then
  echo "ERROR: GNUSTEP_PATHLIST is missing GNUSTEP_SYSTEM_ROOT" >&2
  exit 1
fi

if [[ -z "$INSPECT_ROOT" || ! -d "$INSPECT_ROOT" ]]; then
  echo "ERROR: unable to inspect packaged filesystem for $TARGET" >&2
  exit 1
fi

for required_image in \
  "$INSPECT_ROOT/usr/GNUstep/System/Library/Images/GNUstepMenuImage.tiff" \
  "$INSPECT_ROOT/usr/GNUstep/System/Library/Images/common_ArrowRight.tiff" \
  "$INSPECT_ROOT/usr/GNUstep/System/Library/Images/common_SwitchOn.tiff" \
  "$INSPECT_ROOT/usr/GNUstep/System/Library/Images/common_SwitchOff.tiff"; do
  if [[ ! -f "$required_image" ]]; then
    echo "ERROR: packaged GNUstep image resource missing: $required_image" >&2
    exit 1
  fi
done

while IFS= read -r -d '' file; do
  if readelf -h "$file" >/dev/null 2>&1; then
    inspect_runpath "$file"
  fi
done < <(find \
  "$INSPECT_ROOT/usr/lib" \
  "$INSPECT_ROOT/usr/GNUstep/System/Tools" \
  "$INSPECT_ROOT/usr/GNUstep/System/Library/Bundles" \
  "$INSPECT_ROOT/usr/GNUstep/System/Library/ColorPickers" \
  "$INSPECT_ROOT/usr/GNUstep/System/Library/Themes" \
  -type f -print0)

while IFS= read -r -d '' file; do
  if readelf -h "$file" >/dev/null 2>&1; then
    inspect_ldd_resolves "$file"
  fi
done < <(find \
  "$INSPECT_ROOT/usr/GNUstep/System/Library/ColorPickers" \
  "$INSPECT_ROOT/usr/GNUstep/System/Library/Themes" \
  -type f -print0; \
  find "$INSPECT_ROOT/usr/lib/ObjcMarkdown/MarkdownViewer.app" \
    -type f \
    -name 'MarkdownViewer' \
    -print0; \
  find "$INSPECT_ROOT/usr/GNUstep/System/Library/Bundles" \
    -type f \
    -name 'libgnustep-back-*' \
    -print0; \
  find "$INSPECT_ROOT/usr/bin" \
    -type f \
    -name 'pandoc' \
    -print0)

verify_bundled_pandoc_conversion "$PANDOC_PATH_VALUE" "$PANDOC_DATA_DIR_VALUE"

echo "Validation passed for $TARGET"

#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-}"

if [[ -z "$TARGET" ]]; then
  echo "usage: $0 <AppDir-or-AppImage>" >&2
  exit 1
fi

if [[ -d "$TARGET" ]]; then
  RUN_CMD=("$TARGET/AppRun" --omd-print-runtime-env)
elif [[ -f "$TARGET" ]]; then
  chmod +x "$TARGET"
  RUN_CMD=("$TARGET" --appimage-extract-and-run --omd-print-runtime-env)
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

expect_present_flag APP_BINARY_PRESENT
expect_present_flag DEFAULTS_TOOL_PRESENT
expect_present_flag THEME_BUNDLE_PRESENT
expect_present_flag BACKEND_BUNDLE_PRESENT
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

for required in \
  "$APPDIR_PATH" \
  "$GNUSTEP_SYSTEM_ROOT_PATH" \
  "$GNUSTEP_SYSTEM_LIBRARY_PATH" \
  "$GNUSTEP_SYSTEM_LIBRARIES_PATH" \
  "$GNUSTEP_SYSTEM_TOOLS_PATH"; do
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
  "$GNUSTEP_SYSTEM_TOOLS_PATH"; do
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

echo "Validation passed for $TARGET"

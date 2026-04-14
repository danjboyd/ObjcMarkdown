#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGE_ROOT="${1:-$ROOT/dist/packaging/windows/stage}"

APP_ROOT="$STAGE_ROOT/app"
APP_BUNDLE_DIR="$APP_ROOT/MarkdownViewer.app"
RUNTIME_ROOT="$STAGE_ROOT/runtime"
RUNTIME_BIN_DIR="$RUNTIME_ROOT/bin"
RUNTIME_GNUSTEP_DIR="$RUNTIME_ROOT/lib/GNUstep"
RUNTIME_ETC_DIR="$RUNTIME_ROOT/etc"
RUNTIME_SHARE_DIR="$RUNTIME_ROOT/share"
METADATA_ROOT="$STAGE_ROOT/metadata"
METADATA_DOCS_DIR="$METADATA_ROOT/docs"
METADATA_ICONS_DIR="$METADATA_ROOT/icons"
METADATA_SMOKE_DIR="$METADATA_ROOT/smoke"

copy_required() {
  local source="$1"
  local dest="$2"
  if [[ ! -f "$source" ]]; then
    echo "ERROR: required runtime file not found: $source" >&2
    exit 1
  fi
  cp "$source" "$dest"
}

copy_optional() {
  local source="$1"
  local dest="$2"
  if [[ -f "$source" ]]; then
    cp "$source" "$dest"
  fi
}

rm -rf "$STAGE_ROOT"
mkdir -p \
  "$APP_ROOT" \
  "$RUNTIME_BIN_DIR" \
  "$RUNTIME_GNUSTEP_DIR" \
  "$RUNTIME_ETC_DIR" \
  "$RUNTIME_SHARE_DIR" \
  "$METADATA_DOCS_DIR" \
  "$METADATA_ICONS_DIR" \
  "$METADATA_SMOKE_DIR"

cp -R "$ROOT/ObjcMarkdownViewer/MarkdownViewer.app" "$APP_ROOT/"

copy_required "$ROOT/ObjcMarkdown/obj/ObjcMarkdown-0.dll" "$RUNTIME_BIN_DIR/"
copy_required "$ROOT/third_party/libs-OpenSave/Source/obj/OpenSave-0.dll" "$RUNTIME_BIN_DIR/"
copy_required "$ROOT/third_party/TextViewVimKitBuild/obj/TextViewVimKit-0.dll" "$RUNTIME_BIN_DIR/"
copy_required /clang64/bin/defaults.exe "$RUNTIME_BIN_DIR/"

copy_optional /clang64/bin/libgcc_s_seh-1.dll "$RUNTIME_BIN_DIR/"
copy_optional /clang64/bin/libstdc++-6.dll "$RUNTIME_BIN_DIR/"
copy_optional /clang64/bin/libwinpthread-1.dll "$RUNTIME_BIN_DIR/"
copy_optional /clang64/bin/libc++.dll "$RUNTIME_BIN_DIR/"
copy_optional /clang64/bin/libc++abi.dll "$RUNTIME_BIN_DIR/"
copy_optional /clang64/bin/libunwind.dll "$RUNTIME_BIN_DIR/"

cp -R /clang64/lib/GNUstep/* "$RUNTIME_GNUSTEP_DIR/"
cp -R /clang64/etc/fonts "$RUNTIME_ETC_DIR/"
cp -R /clang64/share/fontconfig "$RUNTIME_SHARE_DIR/"

cp -f "$ROOT/Resources/markdown_icon.ico" "$METADATA_ICONS_DIR/"
cp -f "$ROOT/Resources/markdown_icon.png" "$METADATA_ICONS_DIR/"
if [[ -f "$ROOT/Resources/open-icon.png" ]]; then
  cp -f "$ROOT/Resources/open-icon.png" "$METADATA_ICONS_DIR/"
fi
cp -f "$ROOT/FileAssociations.md" "$METADATA_DOCS_DIR/"
cp -f "$ROOT/Resources/sample-commonmark.md" "$METADATA_SMOKE_DIR/"
printf 'ObjcMarkdown Windows packaging metadata.\n' >"$METADATA_ROOT/README.txt"

declare -A SEEN

is_system_dll() {
  local name="$1"
  case "${name,,}" in
    api-ms-win-*.dll|kernel32.dll|user32.dll|gdi32.dll|shell32.dll|ole32.dll|oleaut32.dll|advapi32.dll|comctl32.dll|comdlg32.dll|ws2_32.dll|mpr.dll|netapi32.dll|bcrypt.dll|secur32.dll|crypt32.dll|uxtheme.dll|dwmapi.dll|shlwapi.dll|setupapi.dll|version.dll|winmm.dll)
      return 0
      ;;
  esac
  return 1
}

find_dll() {
  local name="$1"
  local path=""
  for base in /clang64/bin /clang64/lib /clang64/lib/GNUstep/Libraries/gnustep-base /clang64/lib/GNUstep/Libraries/gnustep-gui; do
    if [[ -f "$base/$name" ]]; then
      path="$base/$name"
      break
    fi
  done
  if [[ -n "$path" ]]; then
    printf '%s\n' "$path"
    return 0
  fi
  return 1
}

collect_deps() {
  local target="$1"
  local dll=""
  if [[ ! -f "$target" ]]; then
    return
  fi

  while read -r dll; do
    if [[ -z "$dll" ]]; then
      continue
    fi
    if is_system_dll "$dll"; then
      continue
    fi
    if [[ "${SEEN[$dll]+yes}" == "yes" ]]; then
      continue
    fi
    SEEN[$dll]=yes
    local path
    if path="$(find_dll "$dll")"; then
      cp -n "$path" "$RUNTIME_BIN_DIR/"
      collect_deps "$path"
    fi
  done < <(objdump -p "$target" 2>/dev/null | awk '/DLL Name:/ {print $3}')
}

collect_deps "$APP_BUNDLE_DIR/MarkdownViewer.exe"
collect_deps "$RUNTIME_BIN_DIR/ObjcMarkdown-0.dll"
collect_deps "$RUNTIME_BIN_DIR/OpenSave-0.dll"
collect_deps "$RUNTIME_BIN_DIR/TextViewVimKit-0.dll"
collect_deps "$RUNTIME_BIN_DIR/defaults.exe"
while IFS= read -r -d '' backend_dll; do
  collect_deps "$backend_dll"
done < <(find "$RUNTIME_GNUSTEP_DIR/Bundles" -type f \( -name 'libgnustep-back-*.dll' -o -name 'libgnustep-back.dll' \) -print0 2>/dev/null)
while IFS= read -r -d '' theme_dll; do
  collect_deps "$theme_dll"
done < <(find "$RUNTIME_GNUSTEP_DIR/Themes" -type f -name '*.dll' -print0 2>/dev/null)

check_debug_crt() {
  local bad=()
  local f
  for f in "$APP_BUNDLE_DIR/MarkdownViewer.exe" "$RUNTIME_BIN_DIR"/*.dll; do
    if [[ ! -f "$f" ]]; then
      continue
    fi
    if objdump -p "$f" 2>/dev/null | grep -Eqi "ucrtbased\.dll|vcruntime140d\.dll"; then
      bad+=("$f")
    fi
  done
  if [[ "${#bad[@]}" -gt 0 ]]; then
    echo "ERROR: debug CRT dependency detected in staged runtime." >&2
    printf '  %s\n' "${bad[@]}" >&2
    exit 1
  fi
}

check_debug_crt

echo "Staged Windows runtime in $STAGE_ROOT"

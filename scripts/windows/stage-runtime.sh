#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGING_DIR="${1:-$ROOT/dist/ObjcMarkdown}"
LAUNCHER_SOURCE="$ROOT/scripts/windows/MarkdownViewerLauncher.c"
LAUNCHER_RESOURCE="$ROOT/scripts/windows/MarkdownViewerLauncher.rc"

APP_DIR="$STAGING_DIR/app"
BIN_DIR="$STAGING_DIR/clang64/bin"
GNUSTEP_DIR="$STAGING_DIR/clang64/lib/GNUstep"
ETC_DIR="$STAGING_DIR/clang64/etc"
SHARE_DIR="$STAGING_DIR/clang64/share"

rm -rf "$STAGING_DIR"
mkdir -p "$APP_DIR" "$BIN_DIR" "$GNUSTEP_DIR" "$ETC_DIR" "$SHARE_DIR"

copy_required() {
  local source="$1"
  local dest="$2"
  if [ ! -f "$source" ]; then
    echo "ERROR: required runtime file not found: $source" >&2
    exit 1
  fi
  cp "$source" "$dest"
}

copy_optional() {
  local source="$1"
  local dest="$2"
  if [ -f "$source" ]; then
    cp "$source" "$dest"
  fi
}

# Copy app bundle
cp -R "$ROOT/ObjcMarkdownViewer/MarkdownViewer.app" "$APP_DIR/"

# Copy project DLLs
cp "$ROOT/ObjcMarkdown/obj/ObjcMarkdown-0.dll" "$BIN_DIR/"
cp "$ROOT/third_party/libs-OpenSave/Source/obj/OpenSave-0.dll" "$BIN_DIR/"
cp "$ROOT/third_party/TextViewVimKitBuild/obj/TextViewVimKit-0.dll" "$BIN_DIR/"
copy_required /clang64/bin/defaults.exe "$BIN_DIR/"
# The exact compiler runtime DLL set varies across MSYS2 clang64 images.
# Copy any known optional runtimes when present, then let recursive dependency
# discovery pull in the rest from the actual binaries we staged.
copy_optional /clang64/bin/libgcc_s_seh-1.dll "$BIN_DIR/"
copy_optional /clang64/bin/libstdc++-6.dll "$BIN_DIR/"
copy_optional /clang64/bin/libwinpthread-1.dll "$BIN_DIR/"
copy_optional /clang64/bin/libc++.dll "$BIN_DIR/"
copy_optional /clang64/bin/libc++abi.dll "$BIN_DIR/"
copy_optional /clang64/bin/libunwind.dll "$BIN_DIR/"

# Copy GNUstep resources (themes, bundles, images, etc.)
cp -R /clang64/lib/GNUstep/* "$GNUSTEP_DIR/"

# Copy runtime config data needed by the GNUstep backend stack on clean machines.
cp -R /clang64/etc/fonts "$ETC_DIR/"
cp -R /clang64/share/fontconfig "$SHARE_DIR/"

# Dependency collection (recursive)
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
    if [ -f "$base/$name" ]; then
      path="$base/$name"
      break
    fi
  done
  if [ -n "$path" ]; then
    echo "$path"
    return 0
  fi
  return 1
}

collect_deps() {
  local target="$1"
  if [ ! -f "$target" ]; then
    return
  fi
  local dll
  while read -r dll; do
    if [ -z "$dll" ]; then
      continue
    fi
    if is_system_dll "$dll"; then
      continue
    fi
    if [ "${SEEN[$dll]+yes}" = "yes" ]; then
      continue
    fi
    SEEN[$dll]=yes
    local path
    if path=$(find_dll "$dll"); then
      cp -n "$path" "$BIN_DIR/"
      collect_deps "$path"
    fi
  done < <(objdump -p "$target" 2>/dev/null | awk '/DLL Name:/ {print $3}')
}

collect_deps "$APP_DIR/MarkdownViewer.app/MarkdownViewer.exe"
collect_deps "$BIN_DIR/ObjcMarkdown-0.dll"
collect_deps "$BIN_DIR/OpenSave-0.dll"
collect_deps "$BIN_DIR/TextViewVimKit-0.dll"
collect_deps "$GNUSTEP_DIR/Bundles/libgnustep-back-031.bundle/libgnustep-back-031.dll"
collect_deps "$GNUSTEP_DIR/Themes/WinUXTheme.theme/WinUXTheme.dll"

check_debug_crt() {
  local bad=()
  local f
  for f in "$APP_DIR/MarkdownViewer.app/MarkdownViewer.exe" "$BIN_DIR"/*.dll; do
    if [ ! -f "$f" ]; then
      continue
    fi
    if objdump -p "$f" 2>/dev/null | grep -Eqi "ucrtbased\.dll|vcruntime140d\.dll"; then
      bad+=("$f")
    fi
  done
  if [ "${#bad[@]}" -gt 0 ]; then
    echo "ERROR: Debug CRT dependency detected in staged runtime." >&2
    printf '  %s\n' "${bad[@]}" >&2
    echo "Fix: ensure MSYS2 clang64 libraries are release builds (no ucrtbased/VCRUNTIME140D)." >&2
    echo "Then restage with this script." >&2
    exit 1
  fi
}

check_debug_crt

build_windows_launcher() {
  local output="$STAGING_DIR/MarkdownViewer.exe"
  local compiler=""
  local rc_compiler=""
  local rc_object=""

  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) ;;
    *)
      return 0
      ;;
  esac

  if command -v clang >/dev/null 2>&1; then
    compiler=clang
  elif command -v cc >/dev/null 2>&1; then
    compiler=cc
  else
    echo "ERROR: no Windows C compiler found to build MarkdownViewer.exe launcher." >&2
    exit 1
  fi

  if command -v llvm-windres >/dev/null 2>&1; then
    rc_compiler=llvm-windres
  elif command -v windres >/dev/null 2>&1; then
    rc_compiler=windres
  fi

  if [ -n "$rc_compiler" ] && [ -f "$LAUNCHER_RESOURCE" ]; then
    rc_object="$STAGING_DIR/MarkdownViewerLauncher-resource.o"
    "$rc_compiler" "$LAUNCHER_RESOURCE" -O coff -o "$rc_object"
    "$compiler" -O2 -municode -mwindows -o "$output" "$LAUNCHER_SOURCE" "$rc_object" -lshlwapi
  else
    "$compiler" -O2 -municode -mwindows -o "$output" "$LAUNCHER_SOURCE" -lshlwapi
  fi
}

build_windows_launcher

# Create launcher for Windows users
cat > "$STAGING_DIR/MarkdownViewer.cmd" <<'CMD'
@echo off
set ROOT=%~dp0
if exist "%ROOT%MarkdownViewer.exe" (
  start "" "%ROOT%MarkdownViewer.exe" %*
  exit /b %ERRORLEVEL%
)
if exist "%ROOT%clang64\bin" (
  set PATH=%ROOT%clang64\bin;%PATH%
  set GNUSTEP_PATHPREFIX_LIST=%ROOT%clang64
) else (
  set PATH=C:\clang64\bin;%PATH%
  set GNUSTEP_PATHPREFIX_LIST=C:\clang64
)
if not defined GSTheme set GSTheme=WinUXTheme
start "" "%ROOT%app\MarkdownViewer.app\MarkdownViewer.exe" %*
CMD

# Portable setup helper
cat > "$STAGING_DIR/PortableSetup.cmd" <<'CMD'
@echo off
set ROOT=%~dp0
if not exist C:\clang64\lib\GNUstep (
  echo Installing GNUstep runtime to C:\clang64...
  xcopy /E /I /Y "%ROOT%clang64" "C:\clang64" >nul
)
echo Done.
CMD

chmod +x "$STAGING_DIR/MarkdownViewer.cmd"

echo "Staged runtime in $STAGING_DIR"

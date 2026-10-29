#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGE_ROOT="${1:-$ROOT/dist/packaging/linux/stage}"
if [[ "$STAGE_ROOT" != /* ]]; then
  STAGE_ROOT="$ROOT/$STAGE_ROOT"
fi
# The Adwaita theme is built from the commit pinned in packaging/inputs.json
# (input "linux-adwaita-theme"), fetched into $THEME_INPUT_DIR. To package
# something else on purpose: a source tree as the second argument or in
# OMD_ADWAITA_THEME_SOURCE (built as it is), or a built Adwaita.theme in
# OMD_ADWAITA_THEME_BUNDLE_SOURCE (copied as it is).
THEME_INPUTS_FILE="$ROOT/packaging/inputs.json"
THEME_INPUT_DIR="$ROOT/dist/packaging/inputs/plugins-themes-Adwaita"
THEME_BUILD_SOURCE="${2:-${OMD_ADWAITA_THEME_SOURCE:-}}"
THEME_BUNDLE_SOURCE="${OMD_ADWAITA_THEME_BUNDLE_SOURCE:-}"
THEME_PROVENANCE=""

APP_ROOT="$STAGE_ROOT/app"
APP_BUNDLE_DIR="$APP_ROOT/MarkdownViewer.app"
APP_LIB_DIR="$APP_ROOT/lib"
RUNTIME_ROOT="$STAGE_ROOT/runtime"
RUNTIME_BIN_DIR="$RUNTIME_ROOT/bin"
RUNTIME_LIB_DIR="$RUNTIME_ROOT/lib"
RUNTIME_SHARE_DIR="$RUNTIME_ROOT/share"
RUNTIME_ETC_DIR="$RUNTIME_ROOT/etc"
RUNTIME_GNUSTEP_ETC_DIR="$RUNTIME_ETC_DIR/GNUstep"
GNUSTEP_SYSTEM_ROOT="$RUNTIME_ROOT/System"
GNUSTEP_LOCAL_ROOT="$RUNTIME_ROOT/Local"
GNUSTEP_NETWORK_ROOT="$RUNTIME_ROOT/Network"
GNUSTEP_LIB_DIR="$GNUSTEP_SYSTEM_ROOT/Library/Libraries"
GNUSTEP_FRAMEWORKS_DIR="$GNUSTEP_SYSTEM_ROOT/Library/Frameworks"
GNUSTEP_BUNDLE_DIR="$GNUSTEP_SYSTEM_ROOT/Library/Bundles"
GNUSTEP_COLORPICKER_DIR="$GNUSTEP_SYSTEM_ROOT/Library/ColorPickers"
GNUSTEP_IMAGES_DIR="$GNUSTEP_SYSTEM_ROOT/Library/Images"
GNUSTEP_KEYBINDINGS_DIR="$GNUSTEP_SYSTEM_ROOT/Library/KeyBindings"
GNUSTEP_THEME_DIR="$GNUSTEP_SYSTEM_ROOT/Library/Themes"
GNUSTEP_TOOLS_DIR="$GNUSTEP_SYSTEM_ROOT/Tools"
GNUSTEP_MAKEFILES_DIR="$GNUSTEP_SYSTEM_ROOT/Library/Makefiles"
FONTCONFIG_ETC_DIR="$RUNTIME_ETC_DIR/fonts"
FONTCONFIG_SHARE_DIR="$RUNTIME_SHARE_DIR/fontconfig"
GLIB_SCHEMA_DIR="$RUNTIME_SHARE_DIR/glib-2.0/schemas"
METADATA_ROOT="$STAGE_ROOT/metadata"
METADATA_DOCS_DIR="$METADATA_ROOT/docs"
METADATA_ICONS_DIR="$METADATA_ROOT/icons"
METADATA_SMOKE_DIR="$METADATA_ROOT/smoke"
PANDOC_BINARY="${OMD_PANDOC_BINARY:-/usr/bin/pandoc}"
PANDOC_SHARE_SOURCE="${OMD_PANDOC_SHARE_SOURCE:-/usr/share/pandoc}"
APP_BINARY="$APP_BUNDLE_DIR/MarkdownViewer"
APP_BINARY_REAL="$APP_BUNDLE_DIR/MarkdownViewer.bin"

require_path() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "ERROR: required path not found: $path" >&2
    exit 1
  fi
}

copy_dir_contents() {
  local source="$1"
  local dest="$2"
  if [[ -d "$source" ]]; then
    mkdir -p "$dest"
    cp -a "$source"/. "$dest"/
  fi
}

# Like copy_glob, but skips what this machine doesn't have.
copy_glob_if_present() {
  local pattern="$1"
  local dest="$2"
  shopt -s nullglob
  local matches=($pattern)
  shopt -u nullglob
  if [[ "${#matches[@]}" -gt 0 ]]; then
    cp -a "${matches[@]}" "$dest"/
  fi
}

copy_glob() {
  local pattern="$1"
  local dest="$2"
  shopt -s nullglob
  local matches=($pattern)
  shopt -u nullglob
  if [[ "${#matches[@]}" -eq 0 ]]; then
    echo "ERROR: no files matched pattern: $pattern" >&2
    exit 1
  fi
  cp -a "${matches[@]}" "$dest"/
}

is_elf_binary() {
  local path="$1"
  readelf -h "$path" >/dev/null 2>&1
}

should_copy_dependency() {
  local path="$1"
  local name
  name="$(basename "$path")"

  case "$path" in
    "$ROOT"/*|"$STAGE_ROOT"/*|/usr/GNUstep/System/Library/Libraries/*)
      return 1
      ;;
  esac

  case "$name" in
    libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|ld-linux*.so*|libgcc_s.so.*|libstdc++.so.*|libresolv.so.*)
      return 1
      ;;
  esac

  return 0
}

copy_library_chain() {
  local source="$1"
  local dest="$2"
  local current="$source"
  local target=""
  local dest_path=""

  while [[ -L "$current" ]]; do
    dest_path="$dest/$(basename "$current")"
    if [[ ! -e "$dest_path" ]]; then
      cp -a "$current" "$dest/"
    fi
    target="$(readlink "$current")"
    if [[ "$target" == /* ]]; then
      current="$target"
    else
      current="$(cd "$(dirname "$current")" && pwd)/$target"
    fi
  done

  dest_path="$dest/$(basename "$current")"
  if [[ ! -e "$dest_path" ]]; then
    cp -a "$current" "$dest/"
  fi
}

copy_elf_dependencies() {
  local binary="$1"
  local dest="$2"
  local dep=""

  while IFS= read -r dep; do
    if [[ -z "$dep" ]]; then
      continue
    fi
    if ! should_copy_dependency "$dep"; then
      continue
    fi
    copy_library_chain "$dep" "$dest"
  done < <(ldd "$binary" 2>/dev/null | awk '/=> \// { print $3 } /^\/[^ ]+/ { print $1 }' | sort -u)
}

copy_shared_by_soname() {
  local soname="$1"
  local dest="$2"
  local resolved=""
  local ldconfig_bin=""

  if command -v ldconfig >/dev/null 2>&1; then
    ldconfig_bin="$(command -v ldconfig)"
  elif [[ -x /sbin/ldconfig ]]; then
    ldconfig_bin="/sbin/ldconfig"
  elif [[ -x /usr/sbin/ldconfig ]]; then
    ldconfig_bin="/usr/sbin/ldconfig"
  else
    return
  fi

  resolved="$("$ldconfig_bin" -p 2>/dev/null | awk -v needle="$soname" '
    $1 == needle && match_found == 0 {
      print $NF
      match_found = 1
    }
  ')"
  if [[ -z "$resolved" ]]; then
    return
  fi
  copy_library_chain "$resolved" "$dest"
}

copy_tree_elf_dependencies() {
  local tree="$1"
  local dest="$2"
  local file=""

  if [[ ! -d "$tree" ]]; then
    return
  fi

  while IFS= read -r -d '' file; do
    if is_elf_binary "$file"; then
      copy_elf_dependencies "$file" "$dest"
    fi
  done < <(find "$tree" -type f -print0)
}

source_host_gnustep() {
  set +u
  . /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
  set -u
}

# Prints the pinned theme input's repo, ref and ref name, one per line.
pinned_theme_input() {
  python3 - "$THEME_INPUTS_FILE" <<'PY'
import json, sys
for item in json.load(open(sys.argv[1]))["inputs"]:
    if item.get("id") == "linux-adwaita-theme":
        print(item["repo"])
        print(item["ref"])
        print(item.get("refName", item["ref"]))
        break
else:
    sys.exit("packaging/inputs.json has no linux-adwaita-theme input")
PY
}

# Checks out the pinned commit in $THEME_INPUT_DIR, fetching only that.
fetch_pinned_theme_source() {
  local input repo ref ref_name
  input="$(pinned_theme_input)"
  repo="$(sed -n 1p <<<"$input")"
  ref="$(sed -n 2p <<<"$input")"
  ref_name="$(sed -n 3p <<<"$input")"

  if [[ ! -d "$THEME_INPUT_DIR/.git" ]]; then
    rm -rf "$THEME_INPUT_DIR"
    mkdir -p "$THEME_INPUT_DIR"
    git -C "$THEME_INPUT_DIR" init -q
  fi
  if ! git -C "$THEME_INPUT_DIR" cat-file -e "$ref^{commit}" 2>/dev/null; then
    git -C "$THEME_INPUT_DIR" fetch -q --depth 1 "$repo" "$ref"
  fi
  git -C "$THEME_INPUT_DIR" checkout -q --force --detach "$ref"
  git -C "$THEME_INPUT_DIR" clean -q -f -d -x

  THEME_BUILD_SOURCE="$THEME_INPUT_DIR"
  THEME_PROVENANCE="Adwaita: $repo at $ref ($ref_name)"
}

install_adwaita_theme() {
  if [[ -n "$THEME_BUNDLE_SOURCE" ]]; then
    require_path "$THEME_BUNDLE_SOURCE/Adwaita"
    mkdir -p "$GNUSTEP_THEME_DIR/Adwaita.theme"
    copy_dir_contents "$THEME_BUNDLE_SOURCE" "$GNUSTEP_THEME_DIR/Adwaita.theme"
    THEME_PROVENANCE="Adwaita: prebuilt bundle from $THEME_BUNDLE_SOURCE (not the pinned input)"
    return
  fi

  if [[ -z "$THEME_BUILD_SOURCE" ]]; then
    fetch_pinned_theme_source
  else
    THEME_PROVENANCE="Adwaita: built from $THEME_BUILD_SOURCE at $(git -C "$THEME_BUILD_SOURCE" rev-parse HEAD 2>/dev/null || echo "an unknown commit") (not the pinned input)"
  fi

  require_path "$THEME_BUILD_SOURCE/GNUmakefile"
  source_host_gnustep

  local temp_install_root
  temp_install_root="$(mktemp -d)"

  gmake -C "$THEME_BUILD_SOURCE" clean >/dev/null
  gmake -C "$THEME_BUILD_SOURCE"
  gmake -C "$THEME_BUILD_SOURCE" install \
    DESTDIR="$temp_install_root" \
    GNUSTEP_INSTALLATION_DOMAIN=SYSTEM >/dev/null

  local installed_theme
  installed_theme="$(find "$temp_install_root" -type d -name 'Adwaita.theme' | head -n 1)"
  if [[ -z "$installed_theme" ]]; then
    echo "ERROR: Adwaita theme install did not produce Adwaita.theme" >&2
    exit 1
  fi

  mkdir -p "$GNUSTEP_THEME_DIR/Adwaita.theme"
  copy_dir_contents "$installed_theme" "$GNUSTEP_THEME_DIR/Adwaita.theme"
  rm -rf "$temp_install_root"
}

require_path /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
require_path "$ROOT/ObjcMarkdownViewer/MarkdownViewer.app/MarkdownViewer"
require_path "$ROOT/ObjcMarkdown/obj/libObjcMarkdown.so"
require_path "$ROOT/third_party/TextViewVimKitBuild/obj/libTextViewVimKit.so"
require_path "$ROOT/Resources/markdown_icon.png"
require_path "$ROOT/Resources/sample-commonmark.md"
require_path "$ROOT/FileAssociations.md"

rm -rf "$STAGE_ROOT"
mkdir -p \
  "$APP_ROOT" \
  "$APP_LIB_DIR" \
  "$RUNTIME_BIN_DIR" \
  "$RUNTIME_LIB_DIR" \
  "$GNUSTEP_LIB_DIR" \
  "$GNUSTEP_FRAMEWORKS_DIR" \
  "$GNUSTEP_BUNDLE_DIR" \
  "$GNUSTEP_COLORPICKER_DIR" \
  "$GNUSTEP_IMAGES_DIR" \
  "$GNUSTEP_THEME_DIR" \
  "$GNUSTEP_TOOLS_DIR" \
  "$GNUSTEP_MAKEFILES_DIR" \
  "$GNUSTEP_LOCAL_ROOT/Library" \
  "$GNUSTEP_LOCAL_ROOT/Library/Libraries" \
  "$GNUSTEP_LOCAL_ROOT/Tools" \
  "$GNUSTEP_NETWORK_ROOT/Library" \
  "$GNUSTEP_NETWORK_ROOT/Library/Libraries" \
  "$GNUSTEP_NETWORK_ROOT/Tools" \
  "$FONTCONFIG_ETC_DIR" \
  "$RUNTIME_GNUSTEP_ETC_DIR" \
  "$FONTCONFIG_SHARE_DIR" \
  "$GLIB_SCHEMA_DIR" \
  "$METADATA_DOCS_DIR" \
  "$METADATA_ICONS_DIR" \
  "$METADATA_SMOKE_DIR"

cp -a "$ROOT/ObjcMarkdownViewer/MarkdownViewer.app" "$APP_ROOT/"
copy_glob "$ROOT/ObjcMarkdown/obj/libObjcMarkdown.so*" "$APP_LIB_DIR"
copy_glob "$ROOT/third_party/TextViewVimKitBuild/obj/libTextViewVimKit.so*" "$APP_LIB_DIR"
copy_glob "$ROOT/third_party/GPUpdaterCore/obj/libGPUpdaterCore.so*" "$APP_LIB_DIR"
copy_glob "$ROOT/third_party/GPUpdaterUI/obj/libGPUpdaterUI.so*" "$APP_LIB_DIR"
copy_shared_by_soname "libicns.so.1" "$RUNTIME_LIB_DIR"

copy_glob "/usr/GNUstep/System/Library/Libraries/libgnustep-base.so*" "$GNUSTEP_LIB_DIR"
copy_glob "/usr/GNUstep/System/Library/Libraries/libgnustep-gui.so*" "$GNUSTEP_LIB_DIR"
# The app links neither; corebase and the SystemPreferences panes (which
# use PreferencePanes) come along only where the build machine has them.
copy_glob_if_present "/usr/GNUstep/System/Library/Libraries/libgnustep-corebase.so*" "$GNUSTEP_LIB_DIR"
copy_glob_if_present "/usr/GNUstep/System/Library/Libraries/libPreferencePanes.so*" "$GNUSTEP_LIB_DIR"
copy_glob "/usr/GNUstep/System/Library/Libraries/libdispatch.so*" "$GNUSTEP_LIB_DIR"
copy_glob "/usr/GNUstep/System/Library/Libraries/libobjc.so*" "$GNUSTEP_LIB_DIR"
copy_glob "/usr/GNUstep/System/Library/Libraries/libBlocksRuntime.so*" "$GNUSTEP_LIB_DIR"

copy_dir_contents "/usr/GNUstep/System/Library/Bundles" "$GNUSTEP_BUNDLE_DIR"
copy_dir_contents "/usr/GNUstep/System/Library/ColorPickers" "$GNUSTEP_COLORPICKER_DIR"
copy_dir_contents "/usr/GNUstep/System/Library/Frameworks/PreferencePanes.framework" "$GNUSTEP_FRAMEWORKS_DIR/PreferencePanes.framework"
copy_dir_contents "/usr/GNUstep/System/Library/Images" "$GNUSTEP_IMAGES_DIR"
# NSTextView's key bindings (DefaultKeyBindings.dict): without them the
# arrows, Home/End, Page Up/Down and Delete do nothing but beep in every
# text view and field; typing and Backspace still work (#288).
require_path "/usr/GNUstep/System/Library/KeyBindings/DefaultKeyBindings.dict"
copy_dir_contents "/usr/GNUstep/System/Library/KeyBindings" "$GNUSTEP_KEYBINDINGS_DIR"
copy_dir_contents "/usr/GNUstep/System/Library/Makefiles" "$GNUSTEP_MAKEFILES_DIR"
# The fallback printer's PPD (PostScript/PPD): without it Export as PDF
# and Print fail on an assertion in GSLPRPrinter and do nothing.
require_path "/usr/GNUstep/System/Library/PostScript/PPD"
copy_dir_contents "/usr/GNUstep/System/Library/PostScript" "$GNUSTEP_SYSTEM_ROOT/Library/PostScript"

if [[ -d /usr/GNUstep/System/Library/Libraries/gnustep-base ]]; then
  mkdir -p "$GNUSTEP_LIB_DIR/gnustep-base"
  copy_dir_contents "/usr/GNUstep/System/Library/Libraries/gnustep-base" "$GNUSTEP_LIB_DIR/gnustep-base"
fi

if [[ -d /usr/GNUstep/System/Library/Libraries/gnustep-gui ]]; then
  mkdir -p "$GNUSTEP_LIB_DIR/gnustep-gui"
  copy_dir_contents "/usr/GNUstep/System/Library/Libraries/gnustep-gui" "$GNUSTEP_LIB_DIR/gnustep-gui"
fi

if [[ -d "$GNUSTEP_BUNDLE_DIR/libgnustep-back-032.bundle" && ! -e "$GNUSTEP_BUNDLE_DIR/libgnustep-back.bundle" ]]; then
  ln -s libgnustep-back-032.bundle "$GNUSTEP_BUNDLE_DIR/libgnustep-back.bundle"
fi

# AppRun seeds the packaged defaults (packagedDefaults.appDomain) with
# runtime/bin/defaults.
require_path /usr/GNUstep/System/Tools/defaults
cp -a /usr/GNUstep/System/Tools/defaults "$GNUSTEP_TOOLS_DIR/"
ln -sf ../System/Tools/defaults "$RUNTIME_BIN_DIR/defaults"

# The tools GNUstep starts on demand: without gdnc the app can't start
# where no GNUstep is installed (or running), gpbs serves the pasteboard
# and make_services builds the Services menu.
for tool in gdnc gpbs make_services; do
  require_path "/usr/GNUstep/System/Tools/$tool"
  cp -a "/usr/GNUstep/System/Tools/$tool" "$GNUSTEP_TOOLS_DIR/"
  copy_elf_dependencies "/usr/GNUstep/System/Tools/$tool" "$RUNTIME_LIB_DIR"
done

if [[ -x "$PANDOC_BINARY" ]]; then
  cp -a "$PANDOC_BINARY" "$RUNTIME_BIN_DIR/pandoc"
  copy_elf_dependencies "$PANDOC_BINARY" "$RUNTIME_LIB_DIR"
  if [[ -d "$PANDOC_SHARE_SOURCE" ]]; then
    mkdir -p "$RUNTIME_SHARE_DIR/pandoc"
    copy_dir_contents "$PANDOC_SHARE_SOURCE" "$RUNTIME_SHARE_DIR/pandoc"
  else
    echo "ERROR: pandoc data directory is required: $PANDOC_SHARE_SOURCE" >&2
    exit 1
  fi
else
  echo "ERROR: pandoc is required to bundle DOCX/ODT/RTF/HTML conversion support." >&2
  exit 1
fi

copy_dir_contents "/etc/fonts" "$FONTCONFIG_ETC_DIR"
copy_dir_contents "/usr/share/fontconfig" "$FONTCONFIG_SHARE_DIR"
copy_dir_contents "/usr/share/glib-2.0/schemas" "$GLIB_SCHEMA_DIR"

cat > "$RUNTIME_GNUSTEP_ETC_DIR/GNUstep.conf" <<EOF
GNUSTEP_USER_CONFIG_FILE=
GNUSTEP_SYSTEM_ROOT="$GNUSTEP_SYSTEM_ROOT"
GNUSTEP_LOCAL_ROOT="$GNUSTEP_LOCAL_ROOT"
GNUSTEP_NETWORK_ROOT="$GNUSTEP_NETWORK_ROOT"
GNUSTEP_SYSTEM_LIBRARY="$GNUSTEP_SYSTEM_ROOT/Library"
GNUSTEP_SYSTEM_LIBRARIES="$GNUSTEP_SYSTEM_ROOT/Library/Libraries"
GNUSTEP_SYSTEM_TOOLS="$GNUSTEP_SYSTEM_ROOT/Tools"
GNUSTEP_LOCAL_LIBRARY="$GNUSTEP_LOCAL_ROOT/Library"
GNUSTEP_LOCAL_LIBRARIES="$GNUSTEP_LOCAL_ROOT/Library/Libraries"
GNUSTEP_LOCAL_TOOLS="$GNUSTEP_LOCAL_ROOT/Tools"
GNUSTEP_NETWORK_LIBRARY="$GNUSTEP_NETWORK_ROOT/Library"
GNUSTEP_NETWORK_LIBRARIES="$GNUSTEP_NETWORK_ROOT/Library/Libraries"
GNUSTEP_NETWORK_TOOLS="$GNUSTEP_NETWORK_ROOT/Tools"
EOF
chmod 0644 "$RUNTIME_GNUSTEP_ETC_DIR/GNUstep.conf"

install_adwaita_theme

copy_elf_dependencies "$APP_BINARY" "$RUNTIME_LIB_DIR"
copy_tree_elf_dependencies "$APP_LIB_DIR" "$RUNTIME_LIB_DIR"
copy_tree_elf_dependencies "$GNUSTEP_BUNDLE_DIR" "$RUNTIME_LIB_DIR"
copy_tree_elf_dependencies "$GNUSTEP_COLORPICKER_DIR" "$RUNTIME_LIB_DIR"
copy_tree_elf_dependencies "$GNUSTEP_THEME_DIR" "$RUNTIME_LIB_DIR"

# GNUstep, the app and its libraries are built with debug info; strip the
# debug info from every staged ELF file (~6.5 MB off the AppImage).
# --strip-debug, not --strip-unneeded: Objective-C methods are local
# symbols, and gdb needs them to name frames.
# The debug info is kept apart first (#132), one file per build ID in the
# layout gdb reads (.build-id/xx/rest.debug), and packed into the package
# root, so CI uploads it with the AppImage and a release attaches it.
if ! command -v strip >/dev/null 2>&1 || ! command -v objcopy >/dev/null 2>&1; then
  echo "ERROR: strip or objcopy not found; install binutils." >&2
  exit 1
fi
DEBUG_ROOT="$ROOT/dist/packaging/linux/debug"
DEBUG_ARCHIVE="$ROOT/dist/packaging/linux/packages/ObjcMarkdown-linux-x86_64.debug.tar.gz"
rm -rf "$DEBUG_ROOT"
mkdir -p "$DEBUG_ROOT" "$(dirname "$DEBUG_ARCHIVE")"
while IFS= read -r -d '' file; do
  if is_elf_binary "$file"; then
    chmod u+w "$file"
    if readelf -S "$file" 2>/dev/null | grep -q '\.debug_info'; then
      build_id="$(readelf -n "$file" 2>/dev/null | sed -n 's/.*Build ID: \([0-9a-f]*\).*/\1/p' | head -n 1)"
      if [[ -n "$build_id" ]]; then
        debug_file="$DEBUG_ROOT/.build-id/${build_id:0:2}/${build_id:2}.debug"
      else
        debug_file="$DEBUG_ROOT/by-path/${file#"$STAGE_ROOT"/}.debug"
      fi
      if [[ ! -e "$debug_file" ]]; then
        mkdir -p "$(dirname "$debug_file")"
        objcopy --only-keep-debug "$file" "$debug_file"
      fi
    fi
    strip --strip-debug "$file"
  fi
done < <(find "$STAGE_ROOT" -type f -print0)
cat > "$DEBUG_ROOT/README.txt" <<'EOF'
Debug info for the MarkdownViewer AppImage these files came with: the
GNUstep libraries, the app and its libraries. Unpack, then in gdb:

  set debug-file-directory /path/to/this/directory
  file /path/to/squashfs-root/usr/app/MarkdownViewer.app/MarkdownViewer.bin
  core /path/to/core   (or: attach PID)

gdb finds each file by build ID. Files without one are under by-path/.
EOF
tar -C "$DEBUG_ROOT" -czf "$DEBUG_ARCHIVE" .
echo "Debug info: $DEBUG_ARCHIVE ($(du -h "$DEBUG_ARCHIVE" | cut -f1))"

mv "$APP_BINARY" "$APP_BINARY_REAL"
cat > "$APP_BINARY" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

APP_BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USR_ROOT="$(cd "$APP_BUNDLE_DIR/../.." && pwd)"
RUNTIME_ROOT="$USR_ROOT/runtime"
CONFIG_ROOT="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/objcmarkdown-gnustep-${UID:-$(id -u)}"
CONFIG_PATH="$CONFIG_ROOT/GNUstep.conf"

mkdir -p "$CONFIG_ROOT"
if [ -L "$CONFIG_ROOT" ] || [ ! -O "$CONFIG_ROOT" ]; then
  CONFIG_ROOT="$(mktemp -d)"
  CONFIG_PATH="$CONFIG_ROOT/GNUstep.conf"
fi
chmod 700 "$CONFIG_ROOT" 2>/dev/null || true

# GNUstep finds gdnc and gpbs through sockets in NSTemporaryDirectory(). With
# the shared /tmp, a host GNUstep's daemons answered instead of the bundled
# ones, and the host's libs-back served the pasteboard without the patches the
# AppImage carries. A private TMPDIR makes the app start its own.
mkdir -p "$CONFIG_ROOT/tmp"
chmod 700 "$CONFIG_ROOT/tmp" 2>/dev/null || true
export TMPDIR="$CONFIG_ROOT/tmp"

# The user Library is the AppImage's own (relative to the home directory, as
# gnustep-packager's gnustepConfig.userLibrary "app" makes it): GNUstep
# searches ~/GNUstep/Library first, so a theme built there against the host's
# GNUstep took the place of the bundled one. The defaults stay in
# ~/GNUstep/Defaults.
cat > "$CONFIG_PATH" <<EOF_CONFIG
GNUSTEP_USER_CONFIG_FILE=
GNUSTEP_SYSTEM_ROOT="$RUNTIME_ROOT/System"
GNUSTEP_LOCAL_ROOT="$RUNTIME_ROOT/Local"
GNUSTEP_NETWORK_ROOT="$RUNTIME_ROOT/Network"
GNUSTEP_SYSTEM_LIBRARY="$RUNTIME_ROOT/System/Library"
GNUSTEP_SYSTEM_LIBRARIES="$RUNTIME_ROOT/System/Library/Libraries"
GNUSTEP_SYSTEM_TOOLS="$RUNTIME_ROOT/System/Tools"
GNUSTEP_LOCAL_LIBRARY="$RUNTIME_ROOT/Local/Library"
GNUSTEP_LOCAL_LIBRARIES="$RUNTIME_ROOT/Local/Library/Libraries"
GNUSTEP_LOCAL_TOOLS="$RUNTIME_ROOT/Local/Tools"
GNUSTEP_NETWORK_LIBRARY="$RUNTIME_ROOT/Network/Library"
GNUSTEP_NETWORK_LIBRARIES="$RUNTIME_ROOT/Network/Library/Libraries"
GNUSTEP_NETWORK_TOOLS="$RUNTIME_ROOT/Network/Tools"
GNUSTEP_USER_DIR_LIBRARY=GNUstep/Library/AppImage/org.objcmarkdown.MarkdownViewer
EOF_CONFIG
chmod 600 "$CONFIG_PATH" 2>/dev/null || true

export GNUSTEP_CONFIG_FILE="$CONFIG_PATH"
exec "$APP_BUNDLE_DIR/MarkdownViewer.bin" "$@"
EOF
chmod 755 "$APP_BINARY"

cp -a "$ROOT/Resources/markdown_icon.png" "$METADATA_ICONS_DIR/"
cp -a "$ROOT/FileAssociations.md" "$METADATA_DOCS_DIR/"
printf '%s\n' "$THEME_PROVENANCE" >"$METADATA_DOCS_DIR/BundledThemes.txt"
echo "$THEME_PROVENANCE"
cp -a "$ROOT/Resources/sample-commonmark.md" "$METADATA_SMOKE_DIR/"
printf 'ObjcMarkdown Linux packaging metadata.\n' >"$METADATA_ROOT/README.txt"

echo "Staged Linux runtime in $STAGE_ROOT"

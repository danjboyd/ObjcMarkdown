#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGE_ROOT="${1:-$ROOT/dist/packaging/linux/stage}"
if [[ "$STAGE_ROOT" != /* ]]; then
  STAGE_ROOT="$ROOT/$STAGE_ROOT"
fi
DEFAULT_THEME_BUILD_SOURCE="$ROOT/third_party/plugins-themes-Adwaita"
if [[ ! -e "$DEFAULT_THEME_BUILD_SOURCE/GNUmakefile" ]]; then
  DEFAULT_THEME_BUILD_SOURCE="$ROOT/../gnustep/plugins-themes-adwaita"
fi
THEME_BUILD_SOURCE="${2:-${OMD_ADWAITA_THEME_SOURCE:-$DEFAULT_THEME_BUILD_SOURCE}}"
THEME_BUNDLE_SOURCE="${OMD_ADWAITA_THEME_BUNDLE_SOURCE:-}"

if [[ -z "$THEME_BUNDLE_SOURCE" ]]; then
  for candidate in \
    "$HOME/GNUstep/Library/Themes/Adwaita.theme" \
    "/usr/GNUstep/Local/Library/Themes/Adwaita.theme" \
    "/usr/GNUstep/System/Library/Themes/Adwaita.theme"; do
    if [[ -e "$candidate/Adwaita" ]]; then
      THEME_BUNDLE_SOURCE="$candidate"
      break
    fi
  done
fi

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

install_adwaita_theme() {
  if [[ -n "$THEME_BUNDLE_SOURCE" ]]; then
    require_path "$THEME_BUNDLE_SOURCE/Adwaita"
    mkdir -p "$GNUSTEP_THEME_DIR/Adwaita.theme"
    copy_dir_contents "$THEME_BUNDLE_SOURCE" "$GNUSTEP_THEME_DIR/Adwaita.theme"
    return
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
require_path "$ROOT/third_party/libs-OpenSave/Source/obj/libOpenSave.so"
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
copy_glob "$ROOT/third_party/libs-OpenSave/Source/obj/libOpenSave.so*" "$APP_LIB_DIR"
copy_glob "$ROOT/third_party/TextViewVimKitBuild/obj/libTextViewVimKit.so*" "$APP_LIB_DIR"
copy_shared_by_soname "libicns.so.1" "$RUNTIME_LIB_DIR"

copy_glob "/usr/GNUstep/System/Library/Libraries/libgnustep-base.so*" "$GNUSTEP_LIB_DIR"
copy_glob "/usr/GNUstep/System/Library/Libraries/libgnustep-gui.so*" "$GNUSTEP_LIB_DIR"
copy_glob "/usr/GNUstep/System/Library/Libraries/libgnustep-corebase.so*" "$GNUSTEP_LIB_DIR"
copy_glob "/usr/GNUstep/System/Library/Libraries/libdispatch.so*" "$GNUSTEP_LIB_DIR"
copy_glob "/usr/GNUstep/System/Library/Libraries/libobjc.so*" "$GNUSTEP_LIB_DIR"
copy_glob "/usr/GNUstep/System/Library/Libraries/libBlocksRuntime.so*" "$GNUSTEP_LIB_DIR"
copy_glob "/usr/GNUstep/System/Library/Libraries/libPreferencePanes.so*" "$GNUSTEP_LIB_DIR"

copy_dir_contents "/usr/GNUstep/System/Library/Bundles" "$GNUSTEP_BUNDLE_DIR"
copy_dir_contents "/usr/GNUstep/System/Library/ColorPickers" "$GNUSTEP_COLORPICKER_DIR"
copy_dir_contents "/usr/GNUstep/System/Library/Frameworks/PreferencePanes.framework" "$GNUSTEP_FRAMEWORKS_DIR/PreferencePanes.framework"
copy_dir_contents "/usr/GNUstep/System/Library/Images" "$GNUSTEP_IMAGES_DIR"
copy_dir_contents "/usr/GNUstep/System/Library/Makefiles" "$GNUSTEP_MAKEFILES_DIR"

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

if [[ -x /usr/GNUstep/System/Tools/defaults ]]; then
  cp -a /usr/GNUstep/System/Tools/defaults "$GNUSTEP_TOOLS_DIR/"
fi

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
chmod 700 "$CONFIG_ROOT" 2>/dev/null || true

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
EOF_CONFIG
chmod 600 "$CONFIG_PATH" 2>/dev/null || true

export GNUSTEP_CONFIG_FILE="$CONFIG_PATH"
exec "$APP_BUNDLE_DIR/MarkdownViewer.bin" "$@"
EOF
chmod 755 "$APP_BINARY"

cp -a "$ROOT/Resources/markdown_icon.png" "$METADATA_ICONS_DIR/"
cp -a "$ROOT/FileAssociations.md" "$METADATA_DOCS_DIR/"
cp -a "$ROOT/Resources/sample-commonmark.md" "$METADATA_SMOKE_DIR/"
printf 'ObjcMarkdown Linux packaging metadata.\n' >"$METADATA_ROOT/README.txt"

echo "Staged Linux runtime in $STAGE_ROOT"

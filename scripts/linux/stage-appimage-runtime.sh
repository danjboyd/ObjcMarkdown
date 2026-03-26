#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGING_DIR="${1:-$ROOT/dist/ObjcMarkdown.AppDir}"
THEME_SOURCE="${2:-${OMD_ADWAITA_THEME_SOURCE:-$ROOT/third_party/plugins-themes-Adwaita}}"

mkdir -p "$(dirname "$STAGING_DIR")"
APPDIR="$(cd "$(dirname "$STAGING_DIR")" && pwd)/$(basename "$STAGING_DIR")"
USR_DIR="$APPDIR/usr"
BIN_DIR="$USR_DIR/bin"
LIB_DIR="$USR_DIR/lib"
APP_BASE_DIR="$USR_DIR/lib/ObjcMarkdown"
APP_BUNDLE_DIR="$APP_BASE_DIR/MarkdownViewer.app"
GNUSTEP_ROOT="$USR_DIR/GNUstep"
GNUSTEP_SYSTEM_ROOT="$GNUSTEP_ROOT/System"
GNUSTEP_LOCAL_ROOT="$GNUSTEP_ROOT/Local"
GNUSTEP_NETWORK_ROOT="$GNUSTEP_ROOT/Network"
GNUSTEP_LIB_DIR="$GNUSTEP_SYSTEM_ROOT/Library/Libraries"
GNUSTEP_BUNDLE_DIR="$GNUSTEP_SYSTEM_ROOT/Library/Bundles"
GNUSTEP_COLORPICKER_DIR="$GNUSTEP_SYSTEM_ROOT/Library/ColorPickers"
GNUSTEP_THEME_DIR="$GNUSTEP_SYSTEM_ROOT/Library/Themes"
GNUSTEP_TOOLS_DIR="$GNUSTEP_SYSTEM_ROOT/Tools"
GNUSTEP_MAKEFILES_DIR="$GNUSTEP_SYSTEM_ROOT/Library/Makefiles"
DESKTOP_DIR="$USR_DIR/share/applications"
ICON_DIR="$USR_DIR/share/icons/hicolor/512x512/apps"
ETC_DIR="$USR_DIR/etc"
SHARE_DIR="$USR_DIR/share"
FONTCONFIG_ETC_DIR="$ETC_DIR/fonts"
FONTCONFIG_SHARE_DIR="$SHARE_DIR/fontconfig"
GLIB_SCHEMA_DIR="$SHARE_DIR/glib-2.0/schemas"
APP_BINARY="$APP_BUNDLE_DIR/MarkdownViewer"
DESKTOP_FILE="$DESKTOP_DIR/objcmarkdown.desktop"
ICON_FILE="$ICON_DIR/objcmarkdown.png"
MANIFEST_FILE="$APPDIR/.omd-appdir-manifest"

require_file() {
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
    "$ROOT"/*|"$APPDIR"/*)
      return 1
      ;;
    /usr/GNUstep/System/Library/Libraries/*)
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

copy_tree_elf_dependencies() {
  local tree="$1"
  local file=""

  if [[ ! -d "$tree" ]]; then
    return
  fi

  while IFS= read -r -d '' file; do
    if is_elf_binary "$file"; then
      copy_elf_dependencies "$file" "$LIB_DIR"
    fi
  done < <(find "$tree" -type f -print0)
}

source_host_gnustep() {
  set +u
  # GNUstep's environment script reads unset variables while bootstrapping.
  . /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
  set -u
}

render_icon() {
  local source="$1"
  local dest="$2"
  local tool=""

  if command -v magick >/dev/null 2>&1; then
    tool="magick"
  elif command -v convert >/dev/null 2>&1; then
    tool="convert"
  else
    echo "ERROR: ImageMagick is required to render the AppImage icon." >&2
    exit 1
  fi

  "$tool" "$source" -resize 512x512 "$dest"
}

install_adwaita_theme() {
  require_file "$THEME_SOURCE/GNUmakefile"

  source_host_gnustep

  gmake -C "$THEME_SOURCE" clean >/dev/null
  gmake -C "$THEME_SOURCE"
  gmake -C "$THEME_SOURCE" install \
    DESTDIR="$APPDIR" \
    GNUSTEP_INSTALLATION_DOMAIN=SYSTEM
}

require_file /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
require_file "$ROOT/ObjcMarkdownViewer/MarkdownViewer.app/MarkdownViewer"
require_file "$ROOT/ObjcMarkdown/obj/libObjcMarkdown.so"
require_file "$ROOT/third_party/libs-OpenSave/Source/obj/libOpenSave.so"
require_file "$ROOT/third_party/TextViewVimKitBuild/obj/libTextViewVimKit.so"

rm -rf "$APPDIR"
mkdir -p \
  "$BIN_DIR" \
  "$LIB_DIR" \
  "$APP_BASE_DIR" \
  "$GNUSTEP_LIB_DIR" \
  "$GNUSTEP_BUNDLE_DIR" \
  "$GNUSTEP_COLORPICKER_DIR" \
  "$GNUSTEP_THEME_DIR" \
  "$GNUSTEP_TOOLS_DIR" \
  "$GNUSTEP_MAKEFILES_DIR" \
  "$DESKTOP_DIR" \
  "$ICON_DIR" \
  "$FONTCONFIG_ETC_DIR" \
  "$FONTCONFIG_SHARE_DIR" \
  "$GLIB_SCHEMA_DIR"

cp -a "$ROOT/ObjcMarkdownViewer/MarkdownViewer.app" "$APP_BASE_DIR/"
copy_glob "$ROOT/ObjcMarkdown/obj/libObjcMarkdown.so*" "$LIB_DIR"
copy_glob "$ROOT/third_party/libs-OpenSave/Source/obj/libOpenSave.so*" "$LIB_DIR"
copy_glob "$ROOT/third_party/TextViewVimKitBuild/obj/libTextViewVimKit.so*" "$LIB_DIR"

copy_glob "/usr/GNUstep/System/Library/Libraries/libgnustep-base.so*" "$GNUSTEP_LIB_DIR"
copy_glob "/usr/GNUstep/System/Library/Libraries/libgnustep-gui.so*" "$GNUSTEP_LIB_DIR"
copy_glob "/usr/GNUstep/System/Library/Libraries/libgnustep-corebase.so*" "$GNUSTEP_LIB_DIR"
copy_glob "/usr/GNUstep/System/Library/Libraries/libdispatch.so*" "$GNUSTEP_LIB_DIR"
copy_glob "/usr/GNUstep/System/Library/Libraries/libobjc.so*" "$GNUSTEP_LIB_DIR"
copy_glob "/usr/GNUstep/System/Library/Libraries/libBlocksRuntime.so*" "$GNUSTEP_LIB_DIR"

copy_dir_contents "/usr/GNUstep/System/Library/Bundles" "$GNUSTEP_BUNDLE_DIR"
copy_dir_contents "/usr/GNUstep/System/Library/ColorPickers" "$GNUSTEP_COLORPICKER_DIR"
copy_dir_contents "/usr/GNUstep/System/Library/Makefiles" "$GNUSTEP_MAKEFILES_DIR"

if [[ -d "$GNUSTEP_BUNDLE_DIR/libgnustep-back-032.bundle" && ! -e "$GNUSTEP_BUNDLE_DIR/libgnustep-back.bundle" ]]; then
  ln -s libgnustep-back-032.bundle "$GNUSTEP_BUNDLE_DIR/libgnustep-back.bundle"
fi

if [[ -x /usr/GNUstep/System/Tools/defaults ]]; then
  cp -a /usr/GNUstep/System/Tools/defaults "$GNUSTEP_TOOLS_DIR/"
fi

if [[ -d /usr/GNUstep/System/Library/Libraries/gnustep-base ]]; then
  mkdir -p "$GNUSTEP_LIB_DIR/gnustep-base"
  copy_dir_contents "/usr/GNUstep/System/Library/Libraries/gnustep-base" "$GNUSTEP_LIB_DIR/gnustep-base"
fi

if [[ -d /usr/GNUstep/System/Library/Libraries/gnustep-gui ]]; then
  mkdir -p "$GNUSTEP_LIB_DIR/gnustep-gui"
  copy_dir_contents "/usr/GNUstep/System/Library/Libraries/gnustep-gui" "$GNUSTEP_LIB_DIR/gnustep-gui"
fi

copy_dir_contents "/etc/fonts" "$FONTCONFIG_ETC_DIR"
copy_dir_contents "/usr/share/fontconfig" "$FONTCONFIG_SHARE_DIR"
copy_dir_contents "/usr/share/glib-2.0/schemas" "$GLIB_SCHEMA_DIR"

install_adwaita_theme
copy_tree_elf_dependencies "$GNUSTEP_BUNDLE_DIR"
copy_tree_elf_dependencies "$GNUSTEP_COLORPICKER_DIR"
copy_tree_elf_dependencies "$GNUSTEP_THEME_DIR"

cat > "$BIN_DIR/MarkdownViewer" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${APPDIR:-}" && -d "${APPDIR}/usr" ]]; then
  OMD_APPDIR="$APPDIR"
else
  OMD_APPDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

OMD_GNUSTEP_ROOT="$OMD_APPDIR/usr/GNUstep"
OMD_GNUSTEP_SYSTEM_ROOT="$OMD_GNUSTEP_ROOT/System"
OMD_GNUSTEP_LOCAL_ROOT="$OMD_GNUSTEP_ROOT/Local"
OMD_GNUSTEP_NETWORK_ROOT="$OMD_GNUSTEP_ROOT/Network"
OMD_GNUSTEP_USER_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/objcmarkdown-appimage/GNUstep"
OMD_GNUSTEP_SYSTEM_LIBRARY="$OMD_GNUSTEP_SYSTEM_ROOT/Library"
OMD_GNUSTEP_SYSTEM_LIBRARIES="$OMD_GNUSTEP_SYSTEM_LIBRARY/Libraries"
OMD_GNUSTEP_SYSTEM_TOOLS="$OMD_GNUSTEP_SYSTEM_ROOT/Tools"
OMD_GNUSTEP_LOCAL_LIBRARY="$OMD_GNUSTEP_LOCAL_ROOT/Library"
OMD_GNUSTEP_LOCAL_LIBRARIES="$OMD_GNUSTEP_LOCAL_LIBRARY/Libraries"
OMD_GNUSTEP_LOCAL_TOOLS="$OMD_GNUSTEP_LOCAL_ROOT/Tools"
OMD_GNUSTEP_NETWORK_LIBRARY="$OMD_GNUSTEP_NETWORK_ROOT/Library"
OMD_GNUSTEP_NETWORK_LIBRARIES="$OMD_GNUSTEP_NETWORK_LIBRARY/Libraries"
OMD_GNUSTEP_NETWORK_TOOLS="$OMD_GNUSTEP_NETWORK_ROOT/Tools"
OMD_GNUSTEP_USER_LIBRARY="$OMD_GNUSTEP_USER_ROOT/Library"
OMD_GNUSTEP_USER_LIBRARIES="$OMD_GNUSTEP_USER_LIBRARY/Libraries"
OMD_GNUSTEP_USER_TOOLS="$OMD_GNUSTEP_USER_ROOT/Tools"
OMD_GNUSTEP_PATHLIST="$OMD_GNUSTEP_USER_ROOT:$OMD_GNUSTEP_LOCAL_ROOT:$OMD_GNUSTEP_NETWORK_ROOT:$OMD_GNUSTEP_SYSTEM_ROOT"
OMD_GNUSTEP_LIB_DIR="$OMD_GNUSTEP_SYSTEM_ROOT/Library/Libraries"
OMD_APP_LIB_DIR="$OMD_APPDIR/usr/lib"
OMD_APP_BINARY="$OMD_APPDIR/usr/lib/ObjcMarkdown/MarkdownViewer.app/MarkdownViewer"
OMD_DEFAULTS_TOOL="$OMD_GNUSTEP_SYSTEM_TOOLS/defaults"
OMD_THEME_BUNDLE="$OMD_GNUSTEP_SYSTEM_ROOT/Library/Themes/Adwaita.theme"
OMD_BACKEND_BUNDLE="$(find "$OMD_GNUSTEP_SYSTEM_ROOT/Library/Bundles" -maxdepth 2 -type f -name 'libgnustep-back-*' | head -n 1)"
OMD_ORIGINAL_LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}"
OMD_RUNTIME_CONFIG_DIR="$OMD_GNUSTEP_USER_ROOT/Runtime"
OMD_RUNTIME_CONFIG="$OMD_RUNTIME_CONFIG_DIR/GNUstep.conf"
OMD_GNUSTEP_USER_RELATIVE_ROOT=".config/objcmarkdown-appimage/GNUstep"

mkdir -p "$OMD_GNUSTEP_USER_ROOT/Defaults/.lck" "$OMD_RUNTIME_CONFIG_DIR"
cat > "$OMD_RUNTIME_CONFIG" <<EOFCONF
GNUSTEP_USER_CONFIG_FILE=
GNUSTEP_USER_DEFAULTS_DIR=$OMD_GNUSTEP_USER_RELATIVE_ROOT/Defaults
GNUSTEP_MAKEFILES=$OMD_GNUSTEP_SYSTEM_ROOT/Library/Makefiles
GNUSTEP_SYSTEM_USERS_DIR=/home
GNUSTEP_NETWORK_USERS_DIR=/home
GNUSTEP_LOCAL_USERS_DIR=/home
GNUSTEP_SYSTEM_APPS=$OMD_GNUSTEP_SYSTEM_ROOT/Applications
GNUSTEP_SYSTEM_ADMIN_APPS=$OMD_GNUSTEP_SYSTEM_ROOT/Applications/Admin
GNUSTEP_SYSTEM_WEB_APPS=$OMD_GNUSTEP_SYSTEM_LIBRARY/WebApplications
GNUSTEP_SYSTEM_TOOLS=$OMD_GNUSTEP_SYSTEM_TOOLS
GNUSTEP_SYSTEM_ADMIN_TOOLS=$OMD_GNUSTEP_SYSTEM_TOOLS/Admin
GNUSTEP_SYSTEM_LIBRARY=$OMD_GNUSTEP_SYSTEM_LIBRARY
GNUSTEP_SYSTEM_HEADERS=$OMD_GNUSTEP_SYSTEM_LIBRARY/Headers
GNUSTEP_SYSTEM_LIBRARIES=$OMD_GNUSTEP_SYSTEM_LIBRARIES
GNUSTEP_SYSTEM_DOC=$OMD_GNUSTEP_SYSTEM_LIBRARY/Documentation
GNUSTEP_SYSTEM_DOC_MAN=$OMD_GNUSTEP_SYSTEM_LIBRARY/Documentation/man
GNUSTEP_SYSTEM_DOC_INFO=$OMD_GNUSTEP_SYSTEM_LIBRARY/Documentation/info
GNUSTEP_NETWORK_APPS=$OMD_GNUSTEP_NETWORK_ROOT/Applications
GNUSTEP_NETWORK_ADMIN_APPS=$OMD_GNUSTEP_NETWORK_ROOT/Applications/Admin
GNUSTEP_NETWORK_WEB_APPS=$OMD_GNUSTEP_NETWORK_LIBRARY/WebApplications
GNUSTEP_NETWORK_TOOLS=$OMD_GNUSTEP_NETWORK_TOOLS
GNUSTEP_NETWORK_ADMIN_TOOLS=$OMD_GNUSTEP_NETWORK_TOOLS/Admin
GNUSTEP_NETWORK_LIBRARY=$OMD_GNUSTEP_NETWORK_LIBRARY
GNUSTEP_NETWORK_HEADERS=$OMD_GNUSTEP_NETWORK_LIBRARY/Headers
GNUSTEP_NETWORK_LIBRARIES=$OMD_GNUSTEP_NETWORK_LIBRARIES
GNUSTEP_NETWORK_DOC=$OMD_GNUSTEP_NETWORK_LIBRARY/Documentation
GNUSTEP_NETWORK_DOC_MAN=$OMD_GNUSTEP_NETWORK_LIBRARY/Documentation/man
GNUSTEP_NETWORK_DOC_INFO=$OMD_GNUSTEP_NETWORK_LIBRARY/Documentation/info
GNUSTEP_LOCAL_APPS=$OMD_GNUSTEP_LOCAL_ROOT/Applications
GNUSTEP_LOCAL_ADMIN_APPS=$OMD_GNUSTEP_LOCAL_ROOT/Applications/Admin
GNUSTEP_LOCAL_WEB_APPS=$OMD_GNUSTEP_LOCAL_LIBRARY/WebApplications
GNUSTEP_LOCAL_TOOLS=$OMD_GNUSTEP_LOCAL_TOOLS
GNUSTEP_LOCAL_ADMIN_TOOLS=$OMD_GNUSTEP_LOCAL_TOOLS/Admin
GNUSTEP_LOCAL_LIBRARY=$OMD_GNUSTEP_LOCAL_LIBRARY
GNUSTEP_LOCAL_HEADERS=$OMD_GNUSTEP_LOCAL_LIBRARY/Headers
GNUSTEP_LOCAL_LIBRARIES=$OMD_GNUSTEP_LOCAL_LIBRARIES
GNUSTEP_LOCAL_DOC=$OMD_GNUSTEP_LOCAL_LIBRARY/Documentation
GNUSTEP_LOCAL_DOC_MAN=$OMD_GNUSTEP_LOCAL_LIBRARY/Documentation/man
GNUSTEP_LOCAL_DOC_INFO=$OMD_GNUSTEP_LOCAL_LIBRARY/Documentation/info
GNUSTEP_USER_DIR_APPS=$OMD_GNUSTEP_USER_RELATIVE_ROOT/Applications
GNUSTEP_USER_DIR_ADMIN_APPS=$OMD_GNUSTEP_USER_RELATIVE_ROOT/Applications/Admin
GNUSTEP_USER_DIR_WEB_APPS=$OMD_GNUSTEP_USER_RELATIVE_ROOT/Library/WebApplications
GNUSTEP_USER_DIR_TOOLS=$OMD_GNUSTEP_USER_RELATIVE_ROOT/Tools
GNUSTEP_USER_DIR_ADMIN_TOOLS=$OMD_GNUSTEP_USER_RELATIVE_ROOT/Tools/Admin
GNUSTEP_USER_DIR_LIBRARY=$OMD_GNUSTEP_USER_RELATIVE_ROOT/Library
GNUSTEP_USER_DIR_HEADERS=$OMD_GNUSTEP_USER_RELATIVE_ROOT/Library/Headers
GNUSTEP_USER_DIR_LIBRARIES=$OMD_GNUSTEP_USER_RELATIVE_ROOT/Library/Libraries
GNUSTEP_USER_DIR_DOC=$OMD_GNUSTEP_USER_RELATIVE_ROOT/Library/Documentation
GNUSTEP_USER_DIR_DOC_MAN=$OMD_GNUSTEP_USER_RELATIVE_ROOT/Library/Documentation/man
GNUSTEP_USER_DIR_DOC_INFO=$OMD_GNUSTEP_USER_RELATIVE_ROOT/Library/Documentation/info
EOFCONF
chmod 600 "$OMD_RUNTIME_CONFIG"

export GNUSTEP_SYSTEM_ROOT="$OMD_GNUSTEP_SYSTEM_ROOT"
export GNUSTEP_LOCAL_ROOT="$OMD_GNUSTEP_LOCAL_ROOT"
export GNUSTEP_NETWORK_ROOT="$OMD_GNUSTEP_NETWORK_ROOT"
export GNUSTEP_USER_ROOT="$OMD_GNUSTEP_USER_ROOT"
export GNUSTEP_PATHLIST="$OMD_GNUSTEP_PATHLIST"
export GNUSTEP_SYSTEM_LIBRARY="$OMD_GNUSTEP_SYSTEM_LIBRARY"
export GNUSTEP_SYSTEM_LIBRARIES="$OMD_GNUSTEP_SYSTEM_LIBRARIES"
export GNUSTEP_SYSTEM_TOOLS="$OMD_GNUSTEP_SYSTEM_TOOLS"
export GNUSTEP_LOCAL_LIBRARY="$OMD_GNUSTEP_LOCAL_LIBRARY"
export GNUSTEP_LOCAL_LIBRARIES="$OMD_GNUSTEP_LOCAL_LIBRARIES"
export GNUSTEP_LOCAL_TOOLS="$OMD_GNUSTEP_LOCAL_TOOLS"
export GNUSTEP_NETWORK_LIBRARY="$OMD_GNUSTEP_NETWORK_LIBRARY"
export GNUSTEP_NETWORK_LIBRARIES="$OMD_GNUSTEP_NETWORK_LIBRARIES"
export GNUSTEP_NETWORK_TOOLS="$OMD_GNUSTEP_NETWORK_TOOLS"
export GNUSTEP_USER_LIBRARY="$OMD_GNUSTEP_USER_LIBRARY"
export GNUSTEP_USER_LIBRARIES="$OMD_GNUSTEP_USER_LIBRARIES"
export GNUSTEP_USER_TOOLS="$OMD_GNUSTEP_USER_TOOLS"
export GNUSTEP_CONFIG_FILE="$OMD_RUNTIME_CONFIG"

unset GNUSTEP_MAKEFILES
unset GNUSTEP_USER_CONFIG_FILE
unset GNUSTEP_KEEP_CONFIG_FILE
unset GNUSTEP_KEEP_USER_CONFIG_FILE

OMD_SANITIZED_LD_LIBRARY_PATH=""
if [[ -n "$OMD_ORIGINAL_LD_LIBRARY_PATH" ]]; then
  IFS=':' read -r -a omd_ld_entries <<< "$OMD_ORIGINAL_LD_LIBRARY_PATH"
  for entry in "${omd_ld_entries[@]}"; do
    if [[ -z "$entry" ]]; then
      continue
    fi
    case "$entry" in
      */GNUstep/Library/Libraries|*/GNUstep/*/Library/Libraries)
        continue
        ;;
      "$OMD_APP_LIB_DIR"|"$OMD_GNUSTEP_LIB_DIR")
        continue
        ;;
    esac
    if [[ -z "$OMD_SANITIZED_LD_LIBRARY_PATH" ]]; then
      OMD_SANITIZED_LD_LIBRARY_PATH="$entry"
    else
      OMD_SANITIZED_LD_LIBRARY_PATH="$OMD_SANITIZED_LD_LIBRARY_PATH:$entry"
    fi
  done
fi

OMD_ORIGINAL_PATH="${PATH:-/usr/bin:/bin}"
OMD_SANITIZED_PATH=""
IFS=':' read -r -a omd_path_entries <<< "$OMD_ORIGINAL_PATH"
for entry in "${omd_path_entries[@]}"; do
  if [[ -z "$entry" ]]; then
    continue
  fi
  case "$entry" in
    */GNUstep/Tools|*/GNUstep/*/Tools)
      continue
      ;;
    "$OMD_APPDIR/usr/bin"|"$OMD_GNUSTEP_SYSTEM_TOOLS")
      continue
      ;;
  esac
  if [[ -z "$OMD_SANITIZED_PATH" ]]; then
    OMD_SANITIZED_PATH="$entry"
  else
    OMD_SANITIZED_PATH="$OMD_SANITIZED_PATH:$entry"
  fi
done

if [[ -n "$OMD_SANITIZED_PATH" ]]; then
  export PATH="$OMD_APPDIR/usr/bin:$OMD_GNUSTEP_SYSTEM_TOOLS:$OMD_SANITIZED_PATH"
else
  export PATH="$OMD_APPDIR/usr/bin:$OMD_GNUSTEP_SYSTEM_TOOLS:/usr/bin:/bin"
fi
if [[ -n "$OMD_SANITIZED_LD_LIBRARY_PATH" ]]; then
  export LD_LIBRARY_PATH="$OMD_APP_LIB_DIR:$OMD_GNUSTEP_LIB_DIR:$OMD_SANITIZED_LD_LIBRARY_PATH"
else
  export LD_LIBRARY_PATH="$OMD_APP_LIB_DIR:$OMD_GNUSTEP_LIB_DIR"
fi
export XDG_DATA_DIRS="$OMD_APPDIR/usr/share${XDG_DATA_DIRS:+:$XDG_DATA_DIRS}"
export FONTCONFIG_PATH="$OMD_APPDIR/usr/etc/fonts"
export GSETTINGS_SCHEMA_DIR="$OMD_APPDIR/usr/share/glib-2.0/schemas"

if [[ -z "${GSTheme:-}" ]]; then
  current_theme=""
  if [[ -x "$OMD_DEFAULTS_TOOL" ]]; then
    current_theme="$("$OMD_DEFAULTS_TOOL" read NSGlobalDomain GSTheme 2>/dev/null || true)"
  fi
  if [[ -z "$current_theme" && -x "$OMD_DEFAULTS_TOOL" ]]; then
    "$OMD_DEFAULTS_TOOL" write NSGlobalDomain GSTheme Adwaita >/dev/null 2>&1 || true
  fi
  export GSTheme=Adwaita
fi

if [[ "${1:-}" == "--omd-print-runtime-env" ]]; then
  cat <<DIAG
APPDIR=$OMD_APPDIR
APP_BINARY=$OMD_APP_BINARY
APP_BINARY_PRESENT=$([[ -x "$OMD_APP_BINARY" ]] && printf '1' || printf '0')
GNUSTEP_SYSTEM_ROOT=${GNUSTEP_SYSTEM_ROOT:-}
GNUSTEP_LOCAL_ROOT=${GNUSTEP_LOCAL_ROOT:-}
GNUSTEP_NETWORK_ROOT=${GNUSTEP_NETWORK_ROOT:-}
GNUSTEP_USER_ROOT=${GNUSTEP_USER_ROOT:-}
GNUSTEP_PATHLIST=${GNUSTEP_PATHLIST:-}
GNUSTEP_SYSTEM_LIBRARY=${GNUSTEP_SYSTEM_LIBRARY:-}
GNUSTEP_SYSTEM_LIBRARIES=${GNUSTEP_SYSTEM_LIBRARIES:-}
GNUSTEP_SYSTEM_TOOLS=${GNUSTEP_SYSTEM_TOOLS:-}
GNUSTEP_CONFIG_FILE=${GNUSTEP_CONFIG_FILE:-}
DEFAULTS_TOOL=$OMD_DEFAULTS_TOOL
DEFAULTS_TOOL_PRESENT=$([[ -x "$OMD_DEFAULTS_TOOL" ]] && printf '1' || printf '0')
GSTheme=${GSTheme:-}
THEME_BUNDLE=$OMD_THEME_BUNDLE
THEME_BUNDLE_PRESENT=$([[ -d "$OMD_THEME_BUNDLE" ]] && printf '1' || printf '0')
BACKEND_BUNDLE=${OMD_BACKEND_BUNDLE:-}
BACKEND_BUNDLE_PRESENT=$([[ -n "${OMD_BACKEND_BUNDLE:-}" && -f "$OMD_BACKEND_BUNDLE" ]] && printf '1' || printf '0')
LD_LIBRARY_PATH=$LD_LIBRARY_PATH
DIAG
  exit 0
fi

exec "$OMD_APP_BINARY" "$@"
EOF

cat > "$APPDIR/AppRun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${APPDIR:-}" && -d "${APPDIR}/usr/bin" ]]; then
  OMD_APPDIR="$APPDIR"
else
  OMD_APPDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

exec "$OMD_APPDIR/usr/bin/MarkdownViewer" "$@"
EOF

cat > "$DESKTOP_FILE" <<'EOF'
[Desktop Entry]
Type=Application
Name=MarkdownViewer
Comment=Open Markdown, RTF, DOCX, and ODT with MarkdownViewer
Exec=MarkdownViewer %F
Terminal=false
StartupNotify=true
StartupWMClass=MarkdownViewer
X-GNOME-WMClass=MarkdownViewer
Categories=Office;Viewer;TextTools;
MimeType=text/markdown;text/x-markdown;application/rtf;text/rtf;application/vnd.openxmlformats-officedocument.wordprocessingml.document;application/vnd.oasis.opendocument.text;
Icon=objcmarkdown
EOF

render_icon "$ROOT/Resources/markdown_icon.png" "$ICON_FILE"
cp -a "$DESKTOP_FILE" "$APPDIR/objcmarkdown.desktop"
cp -a "$ICON_FILE" "$APPDIR/.DirIcon"
chmod +x "$BIN_DIR/MarkdownViewer" "$APPDIR/AppRun"

BACKEND_LIBRARY="$(find "$GNUSTEP_BUNDLE_DIR" -maxdepth 2 -type f -name 'libgnustep-back-*' | head -n 1 || true)"
THEME_LIBRARY="$(find "$GNUSTEP_THEME_DIR/Adwaita.theme" -maxdepth 1 -type f ! -name 'Info-gnustep.plist' ! -name 'stamp.make' | head -n 1 || true)"

cat > "$MANIFEST_FILE" <<EOF
APPDIR=$APPDIR
APP_BINARY=$APP_BINARY
BACKEND_LIBRARY=$BACKEND_LIBRARY
THEME_LIBRARY=$THEME_LIBRARY
DESKTOP_FILE=$DESKTOP_FILE
ICON_FILE=$ICON_FILE
EOF

echo "Staged AppDir in $APPDIR"

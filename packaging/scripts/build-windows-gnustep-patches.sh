#!/usr/bin/env bash
# Builds gnustep-base and gnustep-gui with the fixes in packaging/patches,
# the way MSYS2 builds its CLANG64 packages (mingw-w64-gnustep-base 1.31.1,
# mingw-w64-gnustep-gui 0.32.0: the release tarball, MSYS2's own patch,
# ./configure --prefix, make), and puts the two DLLs in an output directory.
#
# With --install it then replaces the toolchain's DLLs (/clang64/bin) with
# them, so the MSI stages the patched ones. That is only for a throwaway
# toolchain: it refuses unless CI is set (GitHub Actions sets it) or
# OMD_ALLOW_TOOLCHAIN_PATCH=1. Either way it first checks that the
# toolchain's GNUstep is the version the patches are built for, since the
# DLLs must match the headers and the libraries linked against them.
#
# Usage (in an MSYS2 CLANG64 shell):
#   build-windows-gnustep-patches.sh [--install] [--work <dir>] [--out <dir>]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$ROOT/dist/packaging/windows/gnustep-patched"
OUT=""
INSTALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install) INSTALL=1 ;;
    --work) WORK="$2"; shift ;;
    --out) OUT="$2"; shift ;;
    *) echo "usage: $0 [--install] [--work <dir>] [--out <dir>]" >&2; exit 2 ;;
  esac
  shift
done
OUT="${OUT:-$WORK/bin}"
# POSIX paths: MSYS tar takes "C:/..." for a remote host.
if command -v cygpath >/dev/null 2>&1; then
  WORK="$(cygpath -u "$WORK")"
  OUT="$(cygpath -u "$OUT")"
fi

PREFIX="${MINGW_PREFIX:-/clang64}"
BASE_VERSION=1.31.1
GUI_VERSION=0.32.0
BASE_DLL=gnustep-base-1_31.dll
GUI_DLL=gnustep-gui-0.dll

# What MSYS2's PKGBUILDs build from (MINGW-packages, mingw-w64-gnustep-base
# pkgrel 10 and mingw-w64-gnustep-gui pkgrel 7). Base's PKGBUILD also
# applies upstream commit bace6f54, kept in packaging/windows/patches
# (GitHub's generated .patch files aren't byte-stable).
BASE_URL="https://github.com/gnustep/libs-base/releases/download/base-1_31_1/gnustep-base-$BASE_VERSION.tar.gz"
BASE_SHA256=e7546f1c978a7c75b676953a360194a61e921cb45a4804497b4f346a460545cd
BASE_MSYS2_PATCH="$ROOT/packaging/windows/patches/libs-base-bace6f54.patch"
GUI_URL="https://github.com/gnustep/libs-gui/releases/download/gui-0_32_0/gnustep-gui-$GUI_VERSION.tar.gz"
GUI_SHA256=0c03a1b6313babd592ec58fcb825091f77eb27429a4ce4306ec3a7cfa7f9a1f6
CURL_PKG_URL="https://mirror.msys2.org/mingw/clang64/mingw-w64-clang-x86_64-curl-8.22.0-1-any.pkg.tar.zst"
CURL_PKG_SHA256=ce6192a63fbdbd52a6440abcb0d89b81cdaea4a73798b39f569667af27fcb9e4
PKGCONF_PKG_URL="https://mirror.msys2.org/mingw/clang64/mingw-w64-clang-x86_64-pkgconf-1~2.5.1-1-any.pkg.tar.zst"
PKGCONF_PKG_SHA256=6b25519602ce5e799805b3a3c1ade81184b5a7ee2e4b815cd47ce6a2da7b3aeb

die() { echo "build-windows-gnustep-patches: $*" >&2; exit 1; }

if [[ "$INSTALL" == 1 && -z "${CI:-}" && "${OMD_ALLOW_TOOLCHAIN_PATCH:-}" != 1 ]]; then
  die "--install replaces $PREFIX/bin/$BASE_DLL and $GUI_DLL; it only runs in CI or with OMD_ALLOW_TOOLCHAIN_PATCH=1"
fi

# The toolchain's GNUstep must be the version built here.
version_from() { # <header> <prefix>
  local h="$1" p="$2"
  printf '%s.%s.%s' \
    "$(awk -v k="${p}_MAJOR_VERSION" '$0 ~ k {print $NF; exit}' "$h")" \
    "$(awk -v k="${p}_MINOR_VERSION" '$0 ~ k {print $NF; exit}' "$h")" \
    "$(awk -v k="${p}_SUBMINOR_VERSION" '$0 ~ k {print $NF; exit}' "$h")"
}
have_base=$(version_from "$PREFIX/include/GNUstepBase/GSConfig.h" GNUSTEP_BASE)
have_gui=$(version_from "$PREFIX/include/GNUstepGUI/GSVersion.h" GNUSTEP_GUI)
[[ "$have_base" == "$BASE_VERSION" ]] || die "toolchain has gnustep-base $have_base, these patches are for $BASE_VERSION"
[[ "$have_gui" == "$GUI_VERSION" ]] || die "toolchain has gnustep-gui $have_gui, these patches are for $GUI_VERSION"
[[ -f "$PREFIX/bin/$BASE_DLL" && -f "$PREFIX/bin/$GUI_DLL" ]] || die "no $BASE_DLL or $GUI_DLL in $PREFIX/bin"

# Windows' own curl uses the system's certificate store; the packaging
# toolchain's MSYS curl has no CA bundle. Downloads are checksummed anyway.
# (Found through SYSTEMROOT: toolchains mount drives under different prefixes.)
CURL=curl
if [[ -n "${SYSTEMROOT:-}" ]] && command -v cygpath >/dev/null 2>&1; then
  windows_curl="$(cygpath -u "$SYSTEMROOT")/System32/curl.exe"
  if [[ -x "$windows_curl" ]]; then
    CURL="$windows_curl"
  fi
fi
echo "downloading with $CURL"

fetch() { # <url> <sha256> <dest>
  local url="$1" sum="$2" dest="$3"
  if [[ ! -f "$dest" ]] || ! echo "$sum  $dest" | sha256sum -c --status; then
    "$CURL" --fail --location --silent --show-error --retry 3 --output "$dest.part" "$url"
    mv "$dest.part" "$dest"
  fi
  echo "$sum  $dest" | sha256sum -c --status || die "checksum mismatch for $url"
}

mkdir -p "$WORK/downloads" "$OUT"
fetch "$BASE_URL" "$BASE_SHA256" "$WORK/downloads/gnustep-base-$BASE_VERSION.tar.gz"
fetch "$GUI_URL" "$GUI_SHA256" "$WORK/downloads/gnustep-gui-$GUI_VERSION.tar.gz"

# Tools configure needs that a packaging toolchain may lack. They are
# taken from MSYS2's CLANG64 packages (pinned, checksummed) and unpacked
# into the work directory, never into the toolchain.
# OMD_GNUSTEP_PATCHES_SELF_CONTAINED=1 ignores the toolchain's own copies,
# to try what CI does on a box that has them.
SELF_CONTAINED="${OMD_GNUSTEP_PATCHES_SELF_CONTAINED:-}"
unpack() { # <package file> <dest> <paths...>
  local pkg="$1" dest="$2"; shift 2
  rm -rf "$dest"
  mkdir -p "$dest"
  tar --zstd -xf "$pkg" -C "$dest" "$@"
}
# A native Windows program takes Windows paths ("C:/..."); MSYS doesn't
# convert the -I and -L in configure's flags, or pkgconf's search path.
winpath() { cygpath -m "$1"; }

# pkgconf: configure looks pkg-config up on PATH, which on a CI runner can
# find something else (Strawberry Perl's, broken there).
if [[ -z "$SELF_CONTAINED" && -x "$PREFIX/bin/pkgconf.exe" ]]; then
  export PKG_CONFIG="$PREFIX/bin/pkgconf.exe"
else
  fetch "$PKGCONF_PKG_URL" "$PKGCONF_PKG_SHA256" "$WORK/downloads/pkgconf.pkg.tar.zst"
  unpack "$WORK/downloads/pkgconf.pkg.tar.zst" "$WORK/pkgconf" \
    clang64/bin/pkgconf.exe clang64/bin/libpkgconf-7.dll
  export PKG_CONFIG="$WORK/pkgconf/clang64/bin/pkgconf.exe"
fi
pc_path="$(winpath "$PREFIX/lib/pkgconfig");$(winpath "$PREFIX/share/pkgconfig")"
# Some of configure's checks (libffi's) run "pkg-config" by name rather
# than $PKG_CONFIG, so that name comes first on PATH too.
mkdir -p "$WORK/bin-overrides"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$PKG_CONFIG" > "$WORK/bin-overrides/pkg-config"
chmod +x "$WORK/bin-overrides/pkg-config"
export PATH="$WORK/bin-overrides:$PATH"

# gnustep-base's configure insists on libcurl (MSYS2's PKGBUILD has it as a
# make dependency) though, configured like the toolchain's (no libdispatch,
# so no NSURLSession), the library doesn't link it: the import check below
# makes sure. Without curl's development files in the toolchain, MSYS2's
# curl package is unpacked into the work directory just for configure.
if [[ -n "$SELF_CONTAINED" ]] \
   || ! PKG_CONFIG_PATH="$pc_path" "$PKG_CONFIG" --exists libcurl 2>/dev/null; then
  fetch "$CURL_PKG_URL" "$CURL_PKG_SHA256" "$WORK/downloads/curl.pkg.tar.zst"
  unpack "$WORK/downloads/curl.pkg.tar.zst" "$WORK/curl-dev" \
    clang64/include/curl clang64/lib/libcurl.dll.a clang64/lib/pkgconfig/libcurl.pc
  curl_dev="$(winpath "$WORK/curl-dev/clang64")"
  sed -i "s|^prefix=.*|prefix=$curl_dev|" "$WORK/curl-dev/clang64/lib/pkgconfig/libcurl.pc"
  pc_path="$curl_dev/lib/pkgconfig;$pc_path"
  # pkgconf can leave the -I and -L out; give them to configure.
  export CPPFLAGS="-I$curl_dev/include${CPPFLAGS:+ $CPPFLAGS}"
  export LDFLAGS="-L$curl_dev/lib${LDFLAGS:+ $LDFLAGS}"
fi
export PKG_CONFIG_PATH="$pc_path"
"$PKG_CONFIG" --exists libcurl || die "libcurl's development files not found by $PKG_CONFIG"
echo "pkg-config: $PKG_CONFIG; libcurl $("$PKG_CONFIG" --modversion libcurl)"

export CC="$PREFIX/bin/clang" CXX="$PREFIX/bin/clang++"
JOBS="$(nproc 2>/dev/null || echo 2)"

# gnustep-base
rm -rf "$WORK/gnustep-base-$BASE_VERSION"
tar -xzf "$WORK/downloads/gnustep-base-$BASE_VERSION.tar.gz" -C "$WORK"
(
  cd "$WORK/gnustep-base-$BASE_VERSION"
  patch -p1 -i "$BASE_MSYS2_PATCH"
  for p in "$ROOT"/packaging/patches/libs-base/*.patch; do
    patch -p1 -i "$p"
  done
  # Configured as the toolchain's gnustep-base was: an older MSYS2 build
  # may have been made without libdispatch (and so without NSURLSession).
  base_options=()
  if grep -qE '^#define GS_USE_LIBDISPATCH 0' "$PREFIX/include/GNUstepBase/GSConfig.h"; then
    base_options+=(--disable-libdispatch)
  fi
  OBJCFLAGS="-Wno-incompatible-pointer-types" ./configure --prefix="$PREFIX" "${base_options[@]}" \
    > "$WORK/base-configure.log" 2>&1 || { tail -40 "$WORK/base-configure.log"; exit 1; }
  # The same features as the DLL it replaces, or stop.
  if ! diff <(grep -E '^#define' "$PREFIX/include/GNUstepBase/GSConfig.h") \
            <(grep -E '^#define' Headers/GNUstepBase/GSConfig.h); then
    die "gnustep-base configured differently from the toolchain's (GSConfig.h above)"
  fi
  make -j"$JOBS" messages=no > "$WORK/base-make.log" 2>&1 || { grep -iE "error" "$WORK/base-make.log" | head -40; exit 1; }
  dll="$(find . -name "$BASE_DLL" -path '*obj*' | head -1)"
  [[ -n "$dll" ]] || die "the gnustep-base build made no $BASE_DLL"
  cp "$dll" "$OUT/$BASE_DLL"
)

# gnustep-gui, against the toolchain's installed gnustep-base headers and
# import library (the same version; only a .m file differs).
rm -rf "$WORK/gnustep-gui-$GUI_VERSION"
tar -xzf "$WORK/downloads/gnustep-gui-$GUI_VERSION.tar.gz" -C "$WORK"
(
  cd "$WORK/gnustep-gui-$GUI_VERSION"
  for p in "$ROOT"/packaging/patches/libs-gui/*.patch; do
    patch -p1 -i "$p"
  done
  LDFLAGS="-lc++" ./configure --prefix="$PREFIX" > "$WORK/gui-configure.log" 2>&1 \
    || { tail -40 "$WORK/gui-configure.log"; exit 1; }
  make -j"$JOBS" messages=no > "$WORK/gui-make.log" 2>&1 || { grep -iE "error" "$WORK/gui-make.log" | head -40; exit 1; }
  dll="$(find . -name "$GUI_DLL" -path '*obj*' | head -1)"
  [[ -n "$dll" ]] || die "the gnustep-gui build made no $GUI_DLL"
  cp "$dll" "$OUT/$GUI_DLL"
)

# Each DLL must need what the one it replaces needs, no more, no less.
imports() { "$PREFIX/bin/llvm-objdump" -p "$1" | awk '/DLL Name:/ {print $3}' | sort; }
for dll in "$BASE_DLL" "$GUI_DLL"; do
  if ! diff <(imports "$PREFIX/bin/$dll") <(imports "$OUT/$dll"); then
    die "the patched $dll imports different DLLs from the toolchain's (above)"
  fi
done

echo "patched DLLs in $OUT:"
ls -l "$OUT/$BASE_DLL" "$OUT/$GUI_DLL"

if [[ "$INSTALL" == 1 ]]; then
  cp "$OUT/$BASE_DLL" "$PREFIX/bin/$BASE_DLL"
  cp "$OUT/$GUI_DLL" "$PREFIX/bin/$GUI_DLL"
  echo "installed them in $PREFIX/bin"
fi

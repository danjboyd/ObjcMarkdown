#!/usr/bin/env bash
# Usage: check-default-keys.sh
# Checks the in-tree MarkdownViewer's startup defaults (#335) with private
# defaults on a private Xvfb: the theme the app registers still loads, a
# user's choice still wins, and the app writes none of its keys into
# NSGlobalDomain, where they would reach every GNUstep app. It never reads or
# writes your own defaults, and stops only the copies it started.
REPO=$(cd "$(dirname "$0")/../.." && pwd)
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh >/dev/null 2>&1
set -u
APP=$REPO/ObjcMarkdownViewer/MarkdownViewer.app/MarkdownViewer
LIBS=$REPO/ObjcMarkdown/obj:$REPO/third_party/GPUpdaterCore/obj:$REPO/third_party/GPUpdaterUI/obj:$REPO/third_party/TextViewVimKitBuild/obj
KEYS='GSTheme NSMenuInterfaceStyle GSWindowDecoration GSBackChecksOffsetsWithoutNetRequests GSBackChecksOffsetsOnScreen GSSuppressAppIcon'
FAILED=0

# One case: a new defaults directory, GLOBAL (a plist body, or empty for no
# file), then the app with ARGS. Prints what it found and compares.
#   run NAME GLOBAL EXPECT_THEME_LOADED ARGS...
run() {
  local name=$1 global=$2 expect=$3
  shift 3
  local case=$WORK/$name gs=$WORK/$name/gs pid found=no key
  mkdir -p "$gs/Defaults/.lck" "$gs/Library" "$case/tmp"
  grep -v -E '^GNUSTEP_USER_(DEFAULTS_DIR|DIR_LIBRARY)=' /etc/GNUstep/GNUstep.conf > "$gs/GNUstep.conf"
  echo "GNUSTEP_USER_DEFAULTS_DIR=$gs/Defaults" >> "$gs/GNUstep.conf"
  echo "GNUSTEP_USER_DIR_LIBRARY=$gs/Library" >> "$gs/GNUstep.conf"
  chmod 600 "$gs/GNUstep.conf"
  [ -n "$global" ] && printf '%s\n' "$global" > "$gs/Defaults/NSGlobalDomain.plist"
  cp -p "$gs/Defaults/NSGlobalDomain.plist" "$case/before" 2>/dev/null

  env -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS \
    GNUSTEP_CONFIG_FILE="$gs/GNUstep.conf" TEMP="$case/tmp" TMPDIR="$case/tmp" \
    LD_LIBRARY_PATH="$LIBS:${LD_LIBRARY_PATH:-}" \
    "$APP" "$@" > "$case/log" 2>&1 &
  pid=$!
  # The theme's code is mapped into the process when GSTheme loads it.
  for _ in $(seq 1 40); do
    sleep 0.5
    grep -q 'Adwaita\.theme' "/proc/$pid/maps" 2>/dev/null && found=yes
    [ "$found" = yes ] && [ "$expect" = yes ] && break
  done
  sleep 1
  grep -q 'Adwaita\.theme' "/proc/$pid/maps" 2>/dev/null && found=yes
  # Only the copy this case started; a copy that won't quit is killed.
  kill "$pid" 2>/dev/null
  for _ in $(seq 1 10); do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.5
  done
  kill -9 "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null

  local status=ok detail="Adwaita loaded: $found"
  [ "$found" = "$expect" ] || status=FAILED
  if [ -e "$case/before" ]; then
    cmp -s "$case/before" "$gs/Defaults/NSGlobalDomain.plist" || { status=FAILED; detail="$detail; global domain changed"; }
  else
    for key in $KEYS; do
      if grep -q "$key" "$gs/Defaults/NSGlobalDomain.plist" 2>/dev/null; then
        status=FAILED
        detail="$detail; wrote $key"
      fi
    done
  fi
  echo "$status  $name: $detail"
  if [ "$status" != ok ]; then
    FAILED=1
    tail -5 "$case/log" | sed 's/^/    /'
  fi
}

# The app starts GNUstep's gdnc, which outlives it. Stops only the helpers
# started here, recognised by the private work directory in their environment.
stop_helpers() {
  local dir pid
  for dir in /proc/[0-9]*; do
    pid=${dir#/proc/}
    if grep -qaF "GNUSTEP_CONFIG_FILE=$WORK/" "$dir/environ" 2>/dev/null; then
      [ "$pid" != "$$" ] && kill "$pid" 2>/dev/null
    fi
  done
}

check_all() {
  run first-launch '' yes
  run global-gnustep '{ GSTheme = GNUstep; }' no
  run global-adwaita '{ GSTheme = Adwaita; }' yes
  run argument-gnustep '' no -GSTheme GNUstep
}

if [ "${1:-}" = --inside ]; then
  WORK=$(mktemp -d /tmp/omdkeys.XXXXXX)
  trap 'stop_helpers; sleep 1; rm -rf "$WORK"' EXIT
  check_all
  exit $FAILED
fi
exec xvfb-run -a "$0" --inside

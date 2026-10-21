#!/usr/bin/env bash
# Starts a private X display with GNOME Shell as the window manager (X11),
# for driving MarkdownViewer with xdotool and taking screenshots. Detaches;
# writes the display (":120") to $OMD_UI_WORK/display. Stop with ui-stop.sh.
set -u
WORK=${OMD_UI_WORK:-/tmp/omd-ui}
G=$WORK/gsession
mkdir -p $G/{config,data,cache,state,run,gs/glib-2.0/settings} $WORK/shots
chmod 700 $G/run

# Private GNUstep defaults. GNUstep ignores $HOME for its defaults, so the
# app gets its own GNUstep.conf whose defaults directory is in $WORK, seeded
# with a copy of the real global domain (theme, header bar, menu style).
# GNUstep ignores a config file that is group- or world-writable.
# The user Library is private too, so what the app writes there (the
# recovery snapshot in ApplicationSupport) never reaches the real one; only
# the real Library's installed bundles (Themes, Fonts, Bundles, Services)
# are linked in.
GS=$WORK/gnustep
mkdir -p $GS/Defaults/.lck $GS/Library/ApplicationSupport
for name in Themes Fonts Bundles Services; do
  [ -e "$HOME/GNUstep/Library/$name" ] && [ ! -e "$GS/Library/$name" ] && ln -s "$HOME/GNUstep/Library/$name" "$GS/Library/$name"
done
if ! grep -q '^GNUSTEP_USER_DIR_LIBRARY=/' $GS/GNUstep.conf 2>/dev/null; then
  rm -f $GS/GNUstep.conf
  grep -v -E '^GNUSTEP_USER_(DEFAULTS_DIR|DIR_LIBRARY)=' /etc/GNUstep/GNUstep.conf > $GS/GNUstep.conf
  echo "GNUSTEP_USER_DEFAULTS_DIR=$GS/Defaults" >> $GS/GNUstep.conf
  echo "GNUSTEP_USER_DIR_LIBRARY=$GS/Library" >> $GS/GNUstep.conf
  chmod 600 $GS/GNUstep.conf
fi
[ -e $GS/Defaults/NSGlobalDomain.plist ] || cp "$HOME/GNUstep/Defaults/NSGlobalDomain.plist" $GS/Defaults/

# Light by default; ui-dark.sh flips color-scheme before a launch.
[ -e $G/gs/glib-2.0/settings/keyfile ] || cat >$G/gs/glib-2.0/settings/keyfile <<'K'
[org/gnome/desktop/interface]
color-scheme='default'
font-name='Cantarell 11'
[org/gnome/desktop/wm/preferences]
button-layout='appmenu:minimize,maximize,close'
action-double-click-titlebar='toggle-maximize'
K

# No input method in the private session (#143). gnome-shell starts
# ibus-daemon --xim itself, found on PATH, and with every app launch talking
# to it over XIM it grew to gigabytes. The session's PATH starts with a
# directory whose ibus-daemon exits at once; the desktop's ibus is untouched.
mkdir -p $G/bin
printf '#!/bin/sh\n# tools/dev: no input method in the private session (#143).\nexit 0\n' > $G/bin/ibus-daemon
chmod 755 $G/bin/ibus-daemon

for n in $(seq 120 150); do [ ! -e /tmp/.X11-unix/X$n ] && [ ! -e /tmp/.X$n-lock ] && break; done
export DISPLAY=:$n
setsid Xvfb $DISPLAY -screen 0 1600x1000x24 -nolisten tcp +extension GLX +extension RANDR >/dev/null 2>&1 < /dev/null &
sleep 1
setsid env -i HOME="$HOME" PATH="$G/bin:$PATH" DISPLAY="$DISPLAY" XDG_CONFIG_HOME="$G/config" \
  XDG_DATA_HOME="$G/data" XDG_CACHE_HOME="$G/cache" XDG_STATE_HOME="$G/state" \
  XDG_RUNTIME_DIR="$G/run" GSETTINGS_BACKEND=memory LIBGL_ALWAYS_SOFTWARE=1 \
  GIO_USE_VFS=local GVFS_DISABLE_FUSE=1 GIO_USE_VOLUME_MONITOR=unix \
  dbus-run-session -- sh -c 'echo "$DBUS_SESSION_BUS_ADDRESS" > "$1/bus"; exec gnome-shell --x11' sh "$G" \
  >$G/shell.log 2>&1 < /dev/null &
for _ in $(seq 1 60); do xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q "window id" && break; sleep 0.5; done
# Dismiss GNOME's overview and welcome tour.
sleep 4; xdotool key Escape; sleep 1; xdotool key Escape
echo $DISPLAY > $WORK/display
echo "display $DISPLAY ready (work dir $WORK)"

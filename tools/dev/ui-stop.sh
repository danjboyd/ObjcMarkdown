#!/usr/bin/env bash
# Stops the app and everything the private display session started.
# (Never use pkill -f with a pattern here: it can match and kill your shell.)
WORK=${OMD_UI_WORK:-/tmp/omd-ui}
D=$(cat $WORK/display 2>/dev/null)
$(dirname "$0")/ui-stop-app.sh
for p in $(pgrep -u $USER -x gpbs; pgrep -u $USER -x gdnc; pgrep -u $USER -x gnome-shell; pgrep -u $USER -x dbus-daemon); do
  grep -qz "^DISPLAY=$D\$" /proc/$p/environ 2>/dev/null && kill $p
done
for p in $(pgrep -u $USER -x Xvfb); do
  tr '\0' ' ' </proc/$p/cmdline 2>/dev/null | grep -q -- "^Xvfb $D " && kill $p
done
rm -f $WORK/display
echo stopped

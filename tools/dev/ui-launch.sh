#!/usr/bin/env bash
# Usage: ui-launch.sh FILE [extra app args, e.g. -GnomeThemeHeaderBarToolbar NO]
# Starts the in-tree MarkdownViewer on the private display (see ui-session.sh),
# replacing any running one. Its output goes to $OMD_UI_WORK/app.log.
WORK=${OMD_UI_WORK:-/tmp/omd-ui}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
export DISPLAY=$(cat $WORK/display)
# The private session's D-Bus, so portals and other services the app talks
# to are the private session's, never the user's desktop (a file chooser
# would open there).
BUS=$(cat $WORK/gsession/bus 2>/dev/null)
if [ -z "$BUS" ]; then
  echo "no private session bus in $WORK/gsession/bus: restart with ui-stop.sh and ui-session.sh" >&2
  exit 1
fi
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh >/dev/null 2>&1
# Stop only the copy this script started on this display, never the user's.
$(dirname "$0")/ui-stop-app.sh
LIBS=$REPO/ObjcMarkdown/obj:$REPO/third_party/GPUpdaterCore/obj:$REPO/third_party/GPUpdaterUI/obj:$REPO/third_party/libs-OpenSave/Source/obj:$REPO/third_party/TextViewVimKitBuild/obj
cd "$REPO"
DBUS_SESSION_BUS_ADDRESS="$BUS" XDG_RUNTIME_DIR="$WORK/gsession/run" \
  GSETTINGS_BACKEND=keyfile XDG_CONFIG_HOME="$WORK/gsession/gs" \
  GNUSTEP_CONFIG_FILE="$WORK/gnustep/GNUstep.conf" \
  LD_LIBRARY_PATH=$LIBS:/usr/GNUstep/System/Library/Libraries:${LD_LIBRARY_PATH:-} \
  setsid ./ObjcMarkdownViewer/MarkdownViewer.app/MarkdownViewer "$@" >$WORK/app.log 2>&1 < /dev/null &
echo $! > $WORK/app.pid
for _ in $(seq 1 40); do W=$(xdotool search --onlyvisible --class MarkdownViewer 2>/dev/null | tail -1); [ -n "$W" ] && break; sleep 0.5; done
sleep 3; echo "window=${W:-none}"

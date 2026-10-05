#!/usr/bin/env bash
# Usage: ui-launch.sh FILE [extra app args, e.g. -GnomeThemeHeaderBarToolbar NO]
# Starts the in-tree MarkdownViewer on the private display (see ui-session.sh),
# replacing any running one. Its output goes to $OMD_UI_WORK/app.log.
WORK=${OMD_UI_WORK:-/tmp/omd-ui}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
export DISPLAY=$(cat $WORK/display)
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh >/dev/null 2>&1
# Stop only the copy this script started on this display, never the user's.
$(dirname "$0")/ui-stop-app.sh
LIBS=$REPO/ObjcMarkdown/obj:$REPO/third_party/GPUpdaterCore/obj:$REPO/third_party/GPUpdaterUI/obj:$REPO/third_party/libs-OpenSave/Source/obj:$REPO/third_party/TextViewVimKitBuild/obj
cd "$REPO"
GSETTINGS_BACKEND=keyfile XDG_CONFIG_HOME="$WORK/gsession/gs" \
  GNUSTEP_CONFIG_FILE="$WORK/gnustep/GNUstep.conf" \
  LD_LIBRARY_PATH=$LIBS:/usr/GNUstep/System/Library/Libraries:${LD_LIBRARY_PATH:-} \
  setsid ./ObjcMarkdownViewer/MarkdownViewer.app/MarkdownViewer "$@" >$WORK/app.log 2>&1 < /dev/null &
echo $! > $WORK/app.pid
for _ in $(seq 1 40); do W=$(xdotool search --onlyvisible --class MarkdownViewer 2>/dev/null | tail -1); [ -n "$W" ] && break; sleep 0.5; done
sleep 3; echo "window=${W:-none}"

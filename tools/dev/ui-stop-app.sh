#!/usr/bin/env bash
# Stops the MarkdownViewer that ui-launch.sh started, and only that one:
# the recorded process, if it is still MarkdownViewer on the private
# display. A MarkdownViewer the user has open elsewhere is never touched.
WORK=${OMD_UI_WORK:-/tmp/omd-ui}
D=$(cat $WORK/display 2>/dev/null)
P=$(cat $WORK/app.pid 2>/dev/null)
if [ -n "$P" ] && [ -n "$D" ] && [ "$(cat /proc/$P/comm 2>/dev/null)" = MarkdownViewer ] \
   && grep -qz "^DISPLAY=$D\$" /proc/$P/environ 2>/dev/null; then
  kill $P
  for _ in $(seq 1 20); do kill -0 $P 2>/dev/null || break; sleep 0.25; done
  kill -0 $P 2>/dev/null && kill -9 $P
fi
rm -f $WORK/app.pid

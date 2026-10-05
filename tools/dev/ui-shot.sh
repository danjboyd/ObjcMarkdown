#!/usr/bin/env bash
# Usage: ui-shot.sh NAME  -> screenshot of the whole private display at
# $OMD_UI_WORK/shots/NAME.png (prints the path).
WORK=${OMD_UI_WORK:-/tmp/omd-ui}
export DISPLAY=$(cat $WORK/display)
import -window root "$WORK/shots/$1.png" && echo "$WORK/shots/$1.png"

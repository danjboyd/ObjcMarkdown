#!/usr/bin/env bash
# Usage: ui-dark.sh on|off  -> GNOME colour scheme for the next app launch.
# The Adwaita theme reads it at launch only; relaunch after switching.
WORK=${OMD_UI_WORK:-/tmp/omd-ui}
K=$WORK/gsession/gs/glib-2.0/settings/keyfile
if [ "${1:-on}" = on ]; then sed -i "s/'default'/'prefer-dark'/" $K; else sed -i "s/'prefer-dark'/'default'/" $K; fi
grep color-scheme $K

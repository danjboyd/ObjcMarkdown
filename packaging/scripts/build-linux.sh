#!/usr/bin/env bash
set -euo pipefail

set +u
. /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u

gmake OMD_SKIP_TESTS=1

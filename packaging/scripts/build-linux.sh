#!/usr/bin/env bash
set -euo pipefail

resolve_gnustep_makefiles() {
  local candidate=""
  for candidate in \
    "${GNUSTEP_MAKEFILES:-}" \
    "${GP_GNUSTEP_CLI_ROOT:-}/System/Library/Makefiles" \
    "${GP_GNUSTEP_CLI_ROOT:-}/Local/Library/Makefiles" \
    "/usr/GNUstep/System/Library/Makefiles" \
    "/usr/share/GNUstep/Makefiles"; do
    if [[ -n "$candidate" && -f "$candidate/GNUstep.sh" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  echo "ERROR: GNUstep.sh was not found. Expected GNUSTEP_MAKEFILES, GP_GNUSTEP_CLI_ROOT, or a legacy GNUstep install." >&2
  return 1
}

set +u
. "$(resolve_gnustep_makefiles)/GNUstep.sh"
set -u

if command -v gmake >/dev/null 2>&1; then
  gmake OMD_SKIP_TESTS=1
else
  make OMD_SKIP_TESTS=1
fi

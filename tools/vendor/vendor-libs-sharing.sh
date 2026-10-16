#!/usr/bin/env bash
# Copies libs-sharing (danjboyd/libs-sharing) into third_party/libs-sharing
# at a commit, and records it in third_party/libs-sharing/VERSION.
# Usage: tools/vendor/vendor-libs-sharing.sh <path to a libs-sharing checkout> [<commit>]
# Change the shared repository, not the copy here, and copy it again.
set -eu
SRC=$(cd "$1" && pwd)
REF=${2:-HEAD}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DEST=$ROOT/third_party/libs-sharing
COMMIT=$(git -C "$SRC" rev-parse "$REF")
rm -rf "$DEST"
mkdir -p "$DEST"
git -C "$SRC" archive "$COMMIT" GSSharing.make Headers Source Resources LICENSE README.md \
  | tar -x -C "$DEST"
printf 'danjboyd/libs-sharing %s\nCopied by tools/vendor/vendor-libs-sharing.sh; don'"'"'t edit here: change the\nshared repository and copy it again.\n' "$COMMIT" > "$DEST/VERSION"
echo "vendored libs-sharing $COMMIT"

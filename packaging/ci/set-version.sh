#!/usr/bin/env bash
# Usage: set-version.sh VERSION
# Writes a release's version (from its tag, "v" optional) into VERSION
# before a package build, so About and Info-gnustep.plist say what the tag
# says (#119). An empty argument (a run with no tag and no version input)
# keeps VERSION as it is.
set -euo pipefail
cd "$(dirname "$0")/../.."
version="${1:-}"
version="${version#v}"
if [[ -z "$version" ]]; then
  echo "VERSION stays $(cat VERSION)"
  exit 0
fi
# Three or four numbers (a hotfix: 0.2.5.1), and an optional "-rc1" or the like.
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?(-[0-9A-Za-z.]+)?$ ]]; then
  echo "error: not a version: $version" >&2
  exit 1
fi
printf '%s\n' "$version" > VERSION
echo "VERSION set to $version"

#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
gnustep_sh="/usr/GNUstep/System/Library/Makefiles/GNUstep.sh"

if [[ ! -f "${gnustep_sh}" ]]; then
  echo "GNUstep environment script not found at ${gnustep_sh}" >&2
  exit 1
fi

# `GNUstep.sh` is not safe under `set -u`, so source it with nounset disabled.
set +u
# shellcheck disable=SC1090
source "${gnustep_sh}"
set -u

for tool in clang gmake xctest; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "Required tool not found in PATH: ${tool}" >&2
    exit 1
  fi
done

mkdir -p "${HOME}/GNUstep/Defaults/.lck"

runtime_dirs=(
  "${repo_root}/ObjcMarkdown/obj"
  "${repo_root}/third_party/libs-OpenSave/Source/obj"
  "${repo_root}/third_party/TextViewVimKitBuild/obj"
  "/usr/GNUstep/System/Library/Libraries"
)

runtime_path="$(IFS=:; printf '%s' "${runtime_dirs[*]}")"

cd "${repo_root}"
gmake

env \
  LD_LIBRARY_PATH="${runtime_path}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
  xctest ObjcMarkdownTests/ObjcMarkdownTests.bundle

#!/usr/bin/env bash
# Copies the app that was just built, with the project's own DLLs, into a
# new folder under %LOCALAPPDATA%\ObjcMarkdown-dev\builds and makes it the
# current one, which MarkdownViewer-dev.ps1 (the Start-menu launcher)
# runs. The top-level GNUmakefile calls this after a successful build on
# Windows.
#
# The launched app runs from its snapshot, not from the build output, so
# it doesn't lock the DLLs make relinks. Each snapshot is a new folder
# because a running app's files can't be replaced.
#
# usage: snapshot-dev-build.sh <MarkdownViewer.app> <DLL dirs, colon-separated>

set -euo pipefail

app=$1
lib_dirs=$2
keep=3

builds="$(cygpath -F 28)/ObjcMarkdown-dev/builds"
current_file="$builds/current"

if [[ ! -f "$app/MarkdownViewer.exe" ]]; then
  echo "snapshot-dev-build: no $app/MarkdownViewer.exe" >&2
  exit 1
fi

dlls=()
IFS=':' read -r -a dirs <<< "$lib_dirs"
for dir in "${dirs[@]}"; do
  for dll in "$dir"/*.dll; do
    [[ -f "$dll" ]] && dlls+=("$dll")
  done
done

# Same files as the current snapshot: keep it. (Contents, not times: make
# copies the app's resources again on every build.)
same_as_current() {
  local current=$1 dll
  [[ -d "$current/MarkdownViewer.app" ]] || return 1
  diff -rq --exclude=stamp.make --exclude=MarkdownViewer.exe.a \
    "$app" "$current/MarkdownViewer.app" > /dev/null 2>&1 || return 1
  [[ $(ls "$current/lib" | wc -l) -eq ${#dlls[@]} ]] || return 1
  for dll in "${dlls[@]}"; do
    cmp -s "$dll" "$current/lib/$(basename "$dll")" || return 1
  done
}
if [[ -f "$current_file" ]] && same_as_current "$builds/$(cat "$current_file")"; then
  exit 0
fi

name=$(date +%Y%m%d-%H%M%S)
n=1
while [[ -e "$builds/$name" ]]; do
  n=$((n + 1))
  name="$(date +%Y%m%d-%H%M%S)-$n"
done
target="$builds/$name"
mkdir -p "$target/lib"
cp -R "$app" "$target/"
rm -f "$target/MarkdownViewer.app/stamp.make" "$target/MarkdownViewer.app/MarkdownViewer.exe.a"
cp "${dlls[@]}" "$target/lib/"

printf '%s\n' "$name" > "$current_file.tmp"
mv -f "$current_file.tmp" "$current_file"
echo "Snapshot for the Start-menu launcher: $(cygpath -w "$target")"

# Keep the newest few, but never delete one that is running. MSYS2's rm
# and mv succeed on a running program's files; Windows' own del refuses
# to delete a running .exe, so an old snapshot goes only if del removed
# its MarkdownViewer.exe.
for old in $(ls -1d "$builds"/2* 2>/dev/null | sort -r | tail -n +$((keep + 1))); do
  exe="$old/MarkdownViewer.app/MarkdownViewer.exe"
  if [[ -f "$exe" ]]; then
    # The real cmd.exe (in a login shell, cmd is an MSYS2 script), with its
    # arguments left as they are.
    MSYS2_ARG_CONV_EXCL='*' "$(cygpath -u "$SYSTEMROOT")/System32/cmd.exe" /c del /q "$(cygpath -w "$exe")" > /dev/null 2>&1 || true
    [[ -f "$exe" ]] && continue
  fi
  rm -rf "$old" 2>/dev/null || true
done

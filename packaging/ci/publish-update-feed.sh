#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: publish-update-feed.sh <linux|windows> <artifact-directory>

Publishes the single generated *.update-feed.json in <artifact-directory> to
the gh-pages branch at updates/<platform>/stable.json.
USAGE
}

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

platform="$1"
artifact_dir="$2"
case "$platform" in
  linux|windows) ;;
  *)
    usage
    exit 2
    ;;
esac

if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
  echo "GITHUB_REPOSITORY is required." >&2
  exit 1
fi

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "GITHUB_TOKEN is required." >&2
  exit 1
fi

if [[ ! -d "$artifact_dir" ]]; then
  echo "Artifact directory not found: $artifact_dir" >&2
  exit 1
fi

mapfile -t feeds < <(find "$artifact_dir" -maxdepth 1 -type f -name '*.update-feed.json' | sort)
if [[ "${#feeds[@]}" -ne 1 ]]; then
  echo "Expected exactly one *.update-feed.json in $artifact_dir, found ${#feeds[@]}." >&2
  printf '  %s\n' "${feeds[@]}" >&2
  exit 1
fi

feed_path="$(realpath "${feeds[0]}")"
target_branch="${UPDATE_FEED_BRANCH:-gh-pages}"
target_path="updates/$platform/stable.json"
work_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

git init "$work_dir" >/dev/null
cd "$work_dir"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git remote add origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"

if git ls-remote --exit-code --heads origin "$target_branch" >/dev/null 2>&1; then
  git fetch --depth=1 origin "$target_branch" >/dev/null
  git checkout -B "$target_branch" FETCH_HEAD >/dev/null
else
  git checkout --orphan "$target_branch" >/dev/null
fi

mkdir -p "$(dirname "$target_path")"
cp "$feed_path" "$target_path"
touch .nojekyll

git add .nojekyll "$target_path"
if git diff --cached --quiet; then
  echo "No update feed changes to publish for $platform."
  exit 0
fi

git commit -m "Publish $platform stable update feed" >/dev/null

for attempt in 1 2 3; do
  if git push origin "HEAD:$target_branch"; then
    echo "Published $feed_path to $target_branch:$target_path"
    exit 0
  fi

  if [[ "$attempt" -eq 3 ]]; then
    break
  fi

  sleep "$attempt"
  if git ls-remote --exit-code --heads origin "$target_branch" >/dev/null 2>&1; then
    git fetch --depth=1 origin "$target_branch" >/dev/null
    git rebase FETCH_HEAD
  fi
done

echo "Failed to publish update feed after retries." >&2
exit 1

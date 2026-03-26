#!/usr/bin/env bash
set -euo pipefail

MOUNT_LABEL="${OMD_VALIDATION_LABEL:-OBJCMD_VALIDATION}"
WORK_DIR="${OMD_GUEST_VALIDATION_WORKDIR:-${XDG_RUNTIME_DIR:-/tmp}/objcmarkdown-validation}"
MOUNT_PATH=""
SMOKE_GUI=0
SMOKE_DELAY=12

usage() {
  cat <<EOF
usage: $0 [--mount-path PATH] [--smoke-gui] [--smoke-delay SECONDS]
EOF
}

find_validation_mount() {
  local candidates=(
    "/run/media/$USER/$MOUNT_LABEL"
    "/media/$USER/$MOUNT_LABEL"
    "/mnt/$MOUNT_LABEL"
    "/media/$MOUNT_LABEL"
  )
  local path=""

  for path in "${candidates[@]}"; do
    if [[ -d "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done

  while IFS= read -r path; do
    if [[ -d "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done < <(find /run/media /media /mnt -maxdepth 3 -type d -name "$MOUNT_LABEL" 2>/dev/null | sort)

  return 1
}

capture_screenshot() {
  local output="$1"

  if command -v gnome-screenshot >/dev/null 2>&1; then
    gnome-screenshot -f "$output" >/dev/null 2>&1 && return 0
  fi

  if command -v grim >/dev/null 2>&1 && [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    grim "$output" >/dev/null 2>&1 && return 0
  fi

  if command -v import >/dev/null 2>&1 && [[ -n "${DISPLAY:-}" ]]; then
    import -window root "$output" >/dev/null 2>&1 && return 0
  fi

  return 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mount-path)
      MOUNT_PATH="${2:?missing mount path}"
      shift 2
      ;;
    --smoke-gui)
      SMOKE_GUI=1
      shift
      ;;
    --smoke-delay)
      SMOKE_DELAY="${2:?missing smoke delay}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$MOUNT_PATH" ]]; then
  if ! MOUNT_PATH="$(find_validation_mount)"; then
    echo "ERROR: unable to find mounted validation media labeled $MOUNT_LABEL" >&2
    exit 1
  fi
fi

if [[ ! -d "$MOUNT_PATH" ]]; then
  echo "ERROR: validation media mount path not found: $MOUNT_PATH" >&2
  exit 1
fi

APPIMAGE="$(find "$MOUNT_PATH" -maxdepth 1 -type f -name '*.AppImage' | sort | head -n 1)"
VALIDATOR="$MOUNT_PATH/validate-appimage.sh"

if [[ -z "$APPIMAGE" ]]; then
  echo "ERROR: no AppImage found on validation media: $MOUNT_PATH" >&2
  exit 1
fi
if [[ ! -f "$VALIDATOR" ]]; then
  echo "ERROR: validator missing on validation media: $VALIDATOR" >&2
  exit 1
fi

mkdir -p "$WORK_DIR"
LOCAL_APPIMAGE="$WORK_DIR/$(basename "$APPIMAGE")"
cp -f "$APPIMAGE" "$LOCAL_APPIMAGE"
chmod +x "$LOCAL_APPIMAGE"

echo "Running packaged runtime validation from $LOCAL_APPIMAGE"
"$VALIDATOR" "$LOCAL_APPIMAGE"

if [[ "$SMOKE_GUI" -ne 1 ]]; then
  echo "Guest validation completed. Re-run with --smoke-gui for a desktop launch/screenshot."
  exit 0
fi

echo "Launching GUI smoke test for $LOCAL_APPIMAGE"
STDOUT_LOG="$WORK_DIR/gui-stdout.log"
STDERR_LOG="$WORK_DIR/gui-stderr.log"
SCREENSHOT_PATH="$WORK_DIR/gui-smoke.png"

"$LOCAL_APPIMAGE" >"$STDOUT_LOG" 2>"$STDERR_LOG" &
APP_PID=$!
sleep "$SMOKE_DELAY"

if capture_screenshot "$SCREENSHOT_PATH"; then
  echo "Screenshot captured at $SCREENSHOT_PATH"
else
  echo "WARNING: screenshot tool not available in this guest session" >&2
fi

kill "$APP_PID" >/dev/null 2>&1 || true
wait "$APP_PID" >/dev/null 2>&1 || true

echo "GUI smoke logs:"
echo "  stdout: $STDOUT_LOG"
echo "  stderr: $STDERR_LOG"

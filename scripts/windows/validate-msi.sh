#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <path-to-msi>" >&2
  exit 2
fi

MSI_PATH="$1"
if [[ ! -f "$MSI_PATH" ]]; then
  echo "MSI not found: $MSI_PATH" >&2
  exit 2
fi

VM_NAME=${VM_NAME:-iep-abbyy}
SNAPSHOT=${SNAPSHOT:-clean}
BRIDGE_IFACE=${BRIDGE_IFACE:-br0}
HTTP_PORT=${HTTP_PORT:-8000}
WINRM_HOST=${WINRM_HOST:?WINRM_HOST is required}
WINRM_USER=${WINRM_USER:?WINRM_USER is required}
WINRM_PASS=${WINRM_PASS:?WINRM_PASS is required}
WINRM_TRANSPORT=${WINRM_TRANSPORT:-ntlm}
WINRM_PORT=${WINRM_PORT:-5985}
RUN_SMOKE=${RUN_SMOKE:-1}
SKIP_SNAPSHOT=${SKIP_SNAPSHOT:-0}

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TEMP_DIR=$(mktemp -d)
HTTP_LOG=$(mktemp)
HTTP_PID=""

cleanup() {
  if [[ -n "$HTTP_PID" ]]; then
    kill "$HTTP_PID" >/dev/null 2>&1 || true
  fi
  rm -rf "$TEMP_DIR" "$HTTP_LOG"
}
trap cleanup EXIT

cp "$MSI_PATH" "$TEMP_DIR/ObjcMarkdown.msi"
cp "$REPO_ROOT/scripts/windows/validate-msi.ps1" "$TEMP_DIR/validate-msi.ps1"

HOST_IP=$(ip -4 -o addr show "$BRIDGE_IFACE" | awk '{print $4}' | cut -d/ -f1 | head -n1)
if [[ -z "$HOST_IP" ]]; then
  echo "Failed to determine host IP on $BRIDGE_IFACE" >&2
  exit 1
fi

if [[ "$SKIP_SNAPSHOT" != "1" ]]; then
  sudo virsh snapshot-revert "$VM_NAME" "$SNAPSHOT" --running
else
  STATE=$(sudo virsh domstate "$VM_NAME" || true)
  if [[ "$STATE" != "running" ]]; then
    sudo virsh start "$VM_NAME"
  fi
fi

python3 -m http.server "$HTTP_PORT" --bind 0.0.0.0 --directory "$TEMP_DIR" >"$HTTP_LOG" 2>&1 &
HTTP_PID=$!

for _ in $(seq 1 60); do
  if nc -z -w 2 "$WINRM_HOST" "$WINRM_PORT"; then
    break
  fi
  sleep 2
done
if ! nc -z -w 2 "$WINRM_HOST" "$WINRM_PORT"; then
  echo "WinRM not reachable at $WINRM_HOST:$WINRM_PORT" >&2
  exit 1
fi

SMOKE_ARG=""
if [[ "$RUN_SMOKE" == "1" ]]; then
  SMOKE_ARG="-RunSmoke"
fi

read -r -d '' PS_COMMAND <<EOF
$ErrorActionPreference = "Stop"
$dest = "C:\\temp"
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Invoke-WebRequest "http://$HOST_IP:$HTTP_PORT/ObjcMarkdown.msi" -OutFile "$dest\\ObjcMarkdown.msi"
Invoke-WebRequest "http://$HOST_IP:$HTTP_PORT/validate-msi.ps1" -OutFile "$dest\\validate-msi.ps1"
powershell -ExecutionPolicy Bypass -File "$dest\\validate-msi.ps1" -MsiPath "$dest\\ObjcMarkdown.msi" $SMOKE_ARG
EOF

WINRM_HOST="$WINRM_HOST" \
WINRM_USER="$WINRM_USER" \
WINRM_PASS="$WINRM_PASS" \
WINRM_PORT="$WINRM_PORT" \
WINRM_TRANSPORT="$WINRM_TRANSPORT" \
  python3 "$REPO_ROOT/scripts/windows/winrm_run.py" --ps "$PS_COMMAND"

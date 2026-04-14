#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ORACLE_TEST_VMS_ROOT="${ORACLE_TEST_VMS_ROOT:-$ROOT/../OracleTestVMs}"
LEASE_ROOT="$ROOT/dist/otvm/linux"
FIXTURE_NAMES=(
  "Resources/sample-commonmark.md"
  "InlineStyleDemo.md"
  "TableRenderDemo.md"
  "README.md"
)

usage() {
  cat <<EOF
usage: $0 <create|destroy|status> [options]

commands:
  create   Create a Debian OracleTestVMs lease, upload the AppImage and sample Markdown files, and print connection instructions.
  destroy  Destroy a previously created lease.
  status   Print the saved lease JSON or refresh it from OracleTestVMs.

options for create:
  --appimage PATH        Explicit AppImage to upload.
  --ttl-hours N          Lease TTL override passed to otvm create.
  --remote-dir NAME      Directory name under /home/tester for uploaded assets.
  --lease-id ID          Reuse an existing ready lease instead of creating a new one.

options for destroy/status:
  --lease-id ID          Lease identifier.
EOF
}

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $name" >&2
    exit 1
  fi
}

find_latest_appimage() {
  find "$ROOT/dist" "$ROOT" -maxdepth 4 -type f -name 'ObjcMarkdown-*-linux-x86_64.AppImage' 2>/dev/null | sort -r | head -n 1
}

resolve_otvm_bin() {
  if [[ -n "${OTVM_BIN:-}" ]]; then
    printf '%s\n' "$OTVM_BIN"
    return
  fi
  if command -v otvm >/dev/null 2>&1; then
    command -v otvm
    return
  fi
  if [[ -x "$ORACLE_TEST_VMS_ROOT/.venv/bin/otvm" ]]; then
    printf '%s\n' "$ORACLE_TEST_VMS_ROOT/.venv/bin/otvm"
    return
  fi
  echo "ERROR: unable to find otvm. Set OTVM_BIN or create $ORACLE_TEST_VMS_ROOT/.venv/bin/otvm." >&2
  exit 1
}

otvm_invoke() {
  local otvm_bin="$1"
  shift
  if [[ -n "${OTVM_CONFIG:-}" ]]; then
    "$otvm_bin" --config "$OTVM_CONFIG" "$@"
  else
    "$otvm_bin" "$@"
  fi
}

resolve_otvm_private_key() {
  local config_path="${OTVM_CONFIG:-${ORACLETESTVMS_CONFIG:-$HOME/.config/oracletestvms/config.toml}}"
  if [[ ! -f "$config_path" ]]; then
    echo "ERROR: OracleTestVMs config not found: $config_path" >&2
    exit 1
  fi
  python3 - "$config_path" <<'PY'
import sys, tomllib
from pathlib import Path

config_path = Path(sys.argv[1]).expanduser()
with config_path.open("rb") as handle:
    data = tomllib.load(handle)
public_key = (((data.get("project") or {}).get("operator_public_key_file")) or "").strip()
if not public_key:
    raise SystemExit("ERROR: project.operator_public_key_file is missing from " + str(config_path))
key_path = Path(public_key).expanduser()
if key_path.suffix == ".pub":
    key_path = key_path.with_suffix("")
key = str(key_path)
if not key:
    raise SystemExit("ERROR: unable to derive operator private key from " + str(config_path))
print(str(Path(key).expanduser()))
PY
}

json_field() {
  local expr="$1"
  local path="$2"
  jq -r "$expr // empty" "$path"
}

build_fixture_bundle() {
  local bundle_root="$1"
  local docs_root="$bundle_root/sample-markdown"
  mkdir -p "$docs_root"
  for relative in "${FIXTURE_NAMES[@]}"; do
    cp -a "$ROOT/$relative" "$docs_root/"
  done
  cat > "$bundle_root/README.txt" <<EOF
ObjcMarkdown OracleTestVMs validation bundle

Contents:
- app/ObjcMarkdown.AppImage
- sample-markdown/

Suggested manual checks:
1. Mark the AppImage executable and launch it from the tester desktop session.
2. Open each sample Markdown document from sample-markdown/.
3. Confirm headings, inline styles, tables, and larger scrolling documents render correctly.
EOF
}

write_handoff_file() {
  local lease_json="$1"
  local handoff_path="$2"
  local remote_dir="$3"
  local host ssh_port ssh_user gui_user gui_port gui_password lease_id

  lease_id="$(json_field '.lease.lease_id' "$lease_json")"
  host="$(json_field '.lease.remote_access.host' "$lease_json")"
  ssh_port="$(json_field '.lease.remote_access.ssh.port' "$lease_json")"
  ssh_user="$(json_field '.lease.remote_access.ssh.username' "$lease_json")"
  gui_user="$(json_field '.lease.remote_access.gui.username' "$lease_json")"
  gui_port="$(json_field '.lease.remote_access.gui.port' "$lease_json")"
  gui_password="$(json_field '.credentials.gui.secret.password' "$lease_json")"

  cat > "$handoff_path" <<EOF
ObjcMarkdown Linux OracleTestVMs handoff

Lease ID: $lease_id
Host: $host
SSH: ssh -i <operator-private-key> -p $ssh_port $ssh_user@$host
RDP host: $host:$gui_port
RDP username: $gui_user
RDP password: $gui_password

Validation payload location in guest:
/home/tester/$remote_dir

Files in guest:
- /home/tester/$remote_dir/app/ObjcMarkdown.AppImage
- /home/tester/$remote_dir/sample-markdown/

Suggested guest commands after SSH login:
  chmod +x /home/tester/$remote_dir/app/ObjcMarkdown.AppImage
  ls -la /home/tester/$remote_dir/sample-markdown

Suggested RDP checks:
1. Connect with the tester account.
2. Open /home/tester/$remote_dir/app/ObjcMarkdown.AppImage.
3. Open the files under /home/tester/$remote_dir/sample-markdown/.
EOF
}

upload_bundle() {
  local lease_json="$1"
  local bundle_root="$2"
  local remote_dir="$3"
  local ssh_key="$4"
  local host ssh_port ssh_user remote_tmp

  host="$(json_field '.lease.remote_access.host' "$lease_json")"
  ssh_port="$(json_field '.lease.remote_access.ssh.port' "$lease_json")"
  ssh_user="$(json_field '.lease.remote_access.ssh.username' "$lease_json")"
  remote_tmp="/tmp/objcmarkdown-validation-$(basename "$(dirname "$bundle_root")")"

  require_command ssh
  require_command scp

  ssh -p "$ssh_port" -i "$ssh_key" -o StrictHostKeyChecking=accept-new "$ssh_user@$host" "rm -rf '$remote_tmp'"
  scp -P "$ssh_port" -i "$ssh_key" -o StrictHostKeyChecking=accept-new -r "$bundle_root" "$ssh_user@$host:$remote_tmp"
  ssh -p "$ssh_port" -i "$ssh_key" -o StrictHostKeyChecking=accept-new "$ssh_user@$host" \
    "sudo rm -rf '/home/tester/$remote_dir' && sudo mkdir -p '/home/tester/$remote_dir' && sudo cp -a '$remote_tmp/.' '/home/tester/$remote_dir/' && sudo chown -R tester:tester '/home/tester/$remote_dir' && sudo chmod +x '/home/tester/$remote_dir/app/ObjcMarkdown.AppImage' && rm -rf '$remote_tmp'"
}

refresh_status() {
  local otvm_bin="$1"
  local lease_id="$2"
  local output_path="$3"
  otvm_invoke "$otvm_bin" status "$lease_id" > "$output_path"
}

create_cmd() {
  local appimage=""
  local ttl_hours=""
  local remote_dir="ObjcMarkdownValidation"
  local lease_id=""
  local otvm_bin ssh_key bundle_root lease_json handoff_path lease_dir idempotency_key

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --appimage)
        appimage="${2:?missing appimage path}"
        shift 2
        ;;
      --ttl-hours)
        ttl_hours="${2:?missing ttl hours}"
        shift 2
        ;;
      --remote-dir)
        remote_dir="${2:?missing remote dir}"
        shift 2
        ;;
      --lease-id)
        lease_id="${2:?missing lease id}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "ERROR: unknown create option: $1" >&2
        exit 1
        ;;
    esac
  done

  require_command jq
  require_command python3
  otvm_bin="$(resolve_otvm_bin)"
  ssh_key="$(resolve_otvm_private_key)"
  mkdir -p "$LEASE_ROOT"

  if [[ -z "$appimage" ]]; then
    appimage="$(find_latest_appimage)"
  fi
  if [[ -z "$appimage" || ! -f "$appimage" ]]; then
    echo "ERROR: no AppImage found. Build one first or pass --appimage PATH." >&2
    exit 1
  fi

  if [[ -z "$lease_id" ]]; then
    idempotency_key="objcmarkdown-linux-validation-$(date -u +%Y%m%d%H%M%S)"
    lease_json="$(mktemp)"
    if [[ -n "$ttl_hours" ]]; then
      otvm_invoke "$otvm_bin" create debian-13-gnome-wayland --progress human --ttl-hours "$ttl_hours" --idempotency-key "$idempotency_key" --metadata app=ObjcMarkdown --metadata purpose=appimage-validation > "$lease_json"
    else
      otvm_invoke "$otvm_bin" create debian-13-gnome-wayland --progress human --idempotency-key "$idempotency_key" --metadata app=ObjcMarkdown --metadata purpose=appimage-validation > "$lease_json"
    fi
    lease_id="$(json_field '.lease.lease_id' "$lease_json")"
  else
    lease_json="$(mktemp)"
    refresh_status "$otvm_bin" "$lease_id" "$lease_json"
  fi

  if [[ "$(json_field '.lease.status' "$lease_json")" != "ready" ]]; then
    echo "ERROR: lease is not ready: $lease_id" >&2
    cat "$lease_json" >&2
    exit 1
  fi

  lease_dir="$LEASE_ROOT/$lease_id"
  bundle_root="$lease_dir/upload"
  mkdir -p "$bundle_root"
  mkdir -p "$bundle_root/app"
  cp -a "$appimage" "$bundle_root/app/ObjcMarkdown.AppImage"
  build_fixture_bundle "$bundle_root"

  upload_bundle "$lease_json" "$bundle_root" "$remote_dir" "$ssh_key"

  mkdir -p "$lease_dir"
  cp -a "$lease_json" "$lease_dir/lease.json"
  handoff_path="$lease_dir/handoff.txt"
  write_handoff_file "$lease_dir/lease.json" "$handoff_path" "$remote_dir"

  printf 'Lease ready: %s\n' "$lease_id"
  printf 'Lease JSON: %s\n' "$lease_dir/lease.json"
  printf 'Handoff: %s\n' "$handoff_path"
  cat "$handoff_path"
}

destroy_cmd() {
  local lease_id=""
  local otvm_bin
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lease-id)
        lease_id="${2:?missing lease id}"
        shift 2
        ;;
      *)
        if [[ -z "$lease_id" ]]; then
          lease_id="$1"
          shift
        else
          echo "ERROR: unexpected argument: $1" >&2
          exit 1
        fi
        ;;
    esac
  done
  if [[ -z "$lease_id" ]]; then
    echo "ERROR: destroy requires a lease id." >&2
    exit 1
  fi
  otvm_bin="$(resolve_otvm_bin)"
  otvm_invoke "$otvm_bin" destroy "$lease_id"
}

status_cmd() {
  local lease_id=""
  local otvm_bin lease_json
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --lease-id)
        lease_id="${2:?missing lease id}"
        shift 2
        ;;
      *)
        if [[ -z "$lease_id" ]]; then
          lease_id="$1"
          shift
        else
          echo "ERROR: unexpected argument: $1" >&2
          exit 1
        fi
        ;;
    esac
  done
  if [[ -z "$lease_id" ]]; then
    echo "ERROR: status requires a lease id." >&2
    exit 1
  fi
  otvm_bin="$(resolve_otvm_bin)"
  lease_json="$(mktemp)"
  refresh_status "$otvm_bin" "$lease_id" "$lease_json"
  cat "$lease_json"
}

main() {
  local command="${1:-}"
  if [[ -z "$command" ]]; then
    usage
    exit 1
  fi
  shift
  case "$command" in
    create)
      create_cmd "$@"
      ;;
    destroy)
      destroy_cmd "$@"
      ;;
    status)
      status_cmd "$@"
      ;;
    -h|--help|help)
      usage
      ;;
    *)
      echo "ERROR: unknown command: $command" >&2
      usage
      exit 1
      ;;
  esac
}

main "$@"

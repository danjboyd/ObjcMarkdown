#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ORACLE_TEST_VMS_ROOT="${ORACLE_TEST_VMS_ROOT:-$ROOT/../OracleTestVMs}"
LEASE_ROOT="$ROOT/dist/otvm/windows"
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
  create   Create separate Windows build and clean-test OracleTestVMs leases, upload payloads, and print handoff instructions.
  destroy  Destroy one or both previously created leases.
  status   Print the saved lease JSON or refresh it from OracleTestVMs.

options for create:
  --msi PATH                Explicit MSI to upload to the clean test VM.
  --portable-zip PATH       Optional portable ZIP to upload alongside the MSI.
  --source-archive PATH     Explicit source snapshot ZIP for the build VM.
  --ttl-hours N             Lease TTL override passed to otvm create.
  --build-lease-id ID       Reuse an existing ready build lease.
  --test-lease-id ID        Reuse an existing ready clean-test lease.
  --remote-root NAME        Root directory name created on each VM.

options for destroy/status:
  --build-lease-id ID       Build lease identifier.
  --test-lease-id ID        Test lease identifier.
EOF
}

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $name" >&2
    exit 1
  fi
}

zip_with_python() {
  local source_root="$1"
  local zip_path="$2"
  local manifest_path="${3:-}"
  python3 - "$source_root" "$zip_path" "$manifest_path" <<'PY'
import sys
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

source_root = Path(sys.argv[1])
zip_path = Path(sys.argv[2])
manifest_path = Path(sys.argv[3]) if len(sys.argv) > 3 and sys.argv[3] else None

entries = []
if manifest_path is not None:
    entries = [(source_root / line.rstrip("\n")) for line in manifest_path.read_text(encoding="utf-8").splitlines() if line.strip()]
else:
    entries = [path for path in source_root.rglob("*") if path.is_file()]

zip_path.parent.mkdir(parents=True, exist_ok=True)
with ZipFile(zip_path, "w", compression=ZIP_DEFLATED) as archive:
    for path in entries:
        archive.write(path, arcname=path.relative_to(source_root))
PY
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
print(str(key_path.expanduser()))
PY
}

json_field() {
  local expr="$1"
  local path="$2"
  jq -r "$expr // empty" "$path"
}

find_latest_msi() {
  find "$ROOT/dist" -maxdepth 5 -type f -name 'ObjcMarkdown-*-win64.msi' 2>/dev/null | sort -r | head -n 1
}

find_latest_portable_zip() {
  find "$ROOT/dist" -maxdepth 5 -type f -name 'ObjcMarkdown-*-win64-portable.zip' 2>/dev/null | sort -r | head -n 1
}

make_source_archive() {
  local output_path="$1"
  local repo_name="ObjcMarkdown-source"
  local manifest_path
  manifest_path="$(mktemp)"

  require_command git
  rm -f "$output_path"
  (
    cd "$ROOT"
    git ls-files -z --cached --others --exclude-standard \
      | while IFS= read -r -d '' path; do
          [[ "$path" == dist/* ]] && continue
          printf '%s\n' "$path"
        done \
      | sort -u \
      > "$manifest_path"
  )
  if command -v zip >/dev/null 2>&1; then
    (
      cd "$ROOT"
      zip -q "$output_path" -@ < "$manifest_path"
    )
  else
    zip_with_python "$ROOT" "$output_path" "$manifest_path"
  fi
  rm -f "$manifest_path"
  if [[ ! -f "$output_path" ]]; then
    echo "ERROR: failed to create source archive: $output_path" >&2
    exit 1
  fi
  local renamed_path
  renamed_path="$(dirname "$output_path")/${repo_name}.zip"
  mv "$output_path" "$renamed_path"
  printf '%s\n' "$renamed_path"
}

write_build_readme() {
  local path="$1"
  local source_archive_name="$2"
  cat > "$path" <<EOF
ObjcMarkdown Windows build VM handoff

Purpose:
- Use this VM for MSI build reproduction work.
- Keep MSI install validation on the separate clean-test VM.

Prepared assets:
- Desktop\\ObjcMarkdownBuild\\$source_archive_name
- Desktop\\ObjcMarkdownBuild\\build-from-powershell.ps1
- Desktop\\ObjcMarkdownBuild\\windows-msi.manifest.json

Expected toolchain:
- MSYS2 rooted at C:\\msys64
- CLANG64 environment
- GNUstep under C:\\msys64\\clang64

Suggested workflow:
1. Extract $source_archive_name into a writable folder.
2. Install or confirm MSYS2 + CLANG64 + GNUstep prerequisites on this VM.
3. From PowerShell, run:
   .\\build-from-powershell.ps1 -Task test
4. Run the packager pipeline against windows-msi.manifest.json after the sibling gnustep-packager repo is available.

Notes:
- This VM is intentionally separate from the MSI test VM.
- Use the clean-test VM to validate first install and manual GUI behavior.
EOF
}

write_test_readme() {
  local path="$1"
  local msi_name="$2"
  local portable_zip_name="$3"
  cat > "$path" <<EOF
ObjcMarkdown Windows clean-test VM handoff

Prepared assets:
- Desktop\\ObjcMarkdownValidation\\$msi_name
- Desktop\\ObjcMarkdownValidation\\sample-markdown\\
EOF
  if [[ -n "$portable_zip_name" ]]; then
    cat >> "$path" <<EOF
- Desktop\\ObjcMarkdownValidation\\$portable_zip_name
EOF
  fi
  cat >> "$path" <<'EOF'
- Desktop\ObjcMarkdownValidation\validate-msi.ps1

Suggested manual flow:
1. In the RDP session, open Desktop\ObjcMarkdownValidation.
2. Run the MSI normally or from PowerShell with msiexec /i.
3. Launch the installed app.
4. Open the Markdown fixtures under sample-markdown.
5. Confirm window theme/runtime behavior, file open, and rendering.
6. Use validate-msi.ps1 for repeatable unattended install/smoke/uninstall checks if needed.

Upgrade validation note:
- Upgrade testing needs a second MSI build. Keep this VM clean until you are ready to compare an older installer against a newer one.
EOF
}

write_bundle_layout_note() {
  local path="$1"
  cat > "$path" <<'EOF'
ObjcMarkdown Windows OracleTestVMs payload

Files in this folder are staged for the connected operator.
Use the build VM only for packaging work and the clean-test VM only for installer validation.
EOF
}

build_build_bundle() {
  local bundle_root="$1"
  local source_archive="$2"
  mkdir -p "$bundle_root/Desktop/ObjcMarkdownBuild"
  cp -a "$source_archive" "$bundle_root/Desktop/ObjcMarkdownBuild/"
  cp -a "$ROOT/scripts/windows/build-from-powershell.ps1" "$bundle_root/Desktop/ObjcMarkdownBuild/"
  cp -a "$ROOT/packaging/manifests/windows-msi.manifest.json" "$bundle_root/Desktop/ObjcMarkdownBuild/"
  write_build_readme "$bundle_root/Desktop/ObjcMarkdownBuild/README.txt" "$(basename "$source_archive")"
  write_bundle_layout_note "$bundle_root/README.txt"
}

build_test_bundle() {
  local bundle_root="$1"
  local msi_path="$2"
  local portable_zip_path="$3"
  local portable_zip_name=""
  local fixture_root="$bundle_root/Desktop/ObjcMarkdownValidation/sample-markdown"
  mkdir -p "$fixture_root"
  cp -a "$msi_path" "$bundle_root/Desktop/ObjcMarkdownValidation/"
  if [[ -n "$portable_zip_path" ]]; then
    cp -a "$portable_zip_path" "$bundle_root/Desktop/ObjcMarkdownValidation/"
    portable_zip_name="$(basename "$portable_zip_path")"
  fi
  cp -a "$ROOT/scripts/windows/validate-msi.ps1" "$bundle_root/Desktop/ObjcMarkdownValidation/"
  for relative in "${FIXTURE_NAMES[@]}"; do
    cp -a "$ROOT/$relative" "$fixture_root/"
  done
  write_test_readme "$bundle_root/Desktop/ObjcMarkdownValidation/README.txt" "$(basename "$msi_path")" "$portable_zip_name"
  write_bundle_layout_note "$bundle_root/README.txt"
}

zip_bundle() {
  local bundle_root="$1"
  local zip_path="$2"
  rm -f "$zip_path"
  if command -v zip >/dev/null 2>&1; then
    (
      cd "$bundle_root"
      zip -qr "$zip_path" .
    )
  else
    zip_with_python "$bundle_root" "$zip_path"
  fi
}

windows_upload_zip() {
  local lease_json="$1"
  local zip_path="$2"
  local ssh_key="$3"
  local remote_zip_name="$4"
  local host ssh_port ssh_user remote_command

  host="$(json_field '.lease.remote_access.host' "$lease_json")"
  ssh_port="$(json_field '.lease.remote_access.ssh.port' "$lease_json")"
  ssh_user="$(json_field '.lease.remote_access.ssh.username' "$lease_json")"

  scp -P "$ssh_port" -i "$ssh_key" -o StrictHostKeyChecking=accept-new "$zip_path" "$ssh_user@$host:/C:/Users/$ssh_user/$remote_zip_name"

  remote_command=$(cat <<EOF
powershell -NoProfile -ExecutionPolicy Bypass -Command "\$ErrorActionPreference = 'Stop'; \$zip = Join-Path \$HOME '$remote_zip_name'; foreach (\$target in @('C:\\Users\\Public\\Desktop\\ObjcMarkdownBuild','C:\\Users\\Public\\Desktop\\ObjcMarkdownValidation')) { if (Test-Path \$target) { Remove-Item -LiteralPath \$target -Recurse -Force } }; Expand-Archive -LiteralPath \$zip -DestinationPath 'C:\\Users\\Public' -Force; Remove-Item -LiteralPath \$zip -Force"
EOF
)
  ssh -p "$ssh_port" -i "$ssh_key" -o StrictHostKeyChecking=accept-new "$ssh_user@$host" "$remote_command"
}

run_windows_probe() {
  local lease_json="$1"
  local ssh_key="$2"
  local output_path="$3"
  local host ssh_port ssh_user remote_command

  host="$(json_field '.lease.remote_access.host' "$lease_json")"
  ssh_port="$(json_field '.lease.remote_access.ssh.port' "$lease_json")"
  ssh_user="$(json_field '.lease.remote_access.ssh.username' "$lease_json")"

  remote_command='powershell -NoProfile -ExecutionPolicy Bypass -Command "$tools = @{}; foreach ($name in @(\"winget\",\"git\",\"tar\")) { $cmd = Get-Command $name -ErrorAction SilentlyContinue; $tools[$name] = if ($cmd) { $cmd.Source } else { \"\" } }; $paths = @{ msys64 = (Test-Path \"C:\\msys64\"); gnustep = (Test-Path \"C:\\msys64\\clang64\\share\\GNUstep\\Makefiles\\GNUstep.sh\") }; [pscustomobject]@{ tools = $tools; paths = $paths } | ConvertTo-Json -Depth 4"'
  ssh -p "$ssh_port" -i "$ssh_key" -o StrictHostKeyChecking=accept-new "$ssh_user@$host" "$remote_command" > "$output_path"
}

run_remote_validation() {
  local lease_json="$1"
  local ssh_key="$2"
  local lease_dir="$3"
  local msi_name="$4"
  local host ssh_port ssh_user remote_command status

  host="$(json_field '.lease.remote_access.host' "$lease_json")"
  ssh_port="$(json_field '.lease.remote_access.ssh.port' "$lease_json")"
  ssh_user="$(json_field '.lease.remote_access.ssh.username' "$lease_json")"

  mkdir -p "$lease_dir/logs"
  remote_command="powershell -NoProfile -ExecutionPolicy Bypass -File C:\\Users\\Public\\Desktop\\ObjcMarkdownValidation\\validate-msi.ps1 -MsiPath C:\\Users\\Public\\Desktop\\ObjcMarkdownValidation\\$msi_name -RunSmoke"
  set +e
  ssh -p "$ssh_port" -i "$ssh_key" -o StrictHostKeyChecking=accept-new "$ssh_user@$host" "$remote_command" > "$lease_dir/logs/validation.stdout.txt" 2> "$lease_dir/logs/validation.stderr.txt"
  status=$?
  set -e
  scp -P "$ssh_port" -i "$ssh_key" -o StrictHostKeyChecking=accept-new \
    "$ssh_user@$host:C:/temp/omd-logs/install.log" \
    "$ssh_user@$host:C:/temp/omd-logs/uninstall.log" \
    "$lease_dir/logs/" || true
  printf '%s\n' "$status" > "$lease_dir/logs/validation.exitcode"
  return "$status"
}

write_handoff_file() {
  local build_json="$1"
  local test_json="$2"
  local build_probe_json="$3"
  local validation_note="$4"
  local output_path="$5"
  local build_id build_host build_ssh_user build_ssh_port build_gui_user build_gui_port build_gui_password
  local test_id test_host test_ssh_user test_ssh_port test_gui_user test_gui_port test_gui_password

  build_id="$(json_field '.lease.lease_id' "$build_json")"
  build_host="$(json_field '.lease.remote_access.host' "$build_json")"
  build_ssh_user="$(json_field '.lease.remote_access.ssh.username' "$build_json")"
  build_ssh_port="$(json_field '.lease.remote_access.ssh.port' "$build_json")"
  build_gui_user="$(json_field '.credentials.gui.username' "$build_json")"
  build_gui_port="$(json_field '.lease.remote_access.gui.port' "$build_json")"
  build_gui_password="$(json_field '.credentials.gui.secret.password' "$build_json")"

  test_id="$(json_field '.lease.lease_id' "$test_json")"
  test_host="$(json_field '.lease.remote_access.host' "$test_json")"
  test_ssh_user="$(json_field '.lease.remote_access.ssh.username' "$test_json")"
  test_ssh_port="$(json_field '.lease.remote_access.ssh.port' "$test_json")"
  test_gui_user="$(json_field '.credentials.gui.username' "$test_json")"
  test_gui_port="$(json_field '.lease.remote_access.gui.port' "$test_json")"
  test_gui_password="$(json_field '.credentials.gui.secret.password' "$test_json")"

  cat > "$output_path" <<EOF
ObjcMarkdown Windows OracleTestVMs handoff

Build VM
- Lease ID: $build_id
- SSH: ssh -i <operator-private-key> -p $build_ssh_port $build_ssh_user@$build_host
- RDP: $build_host:$build_gui_port
- RDP username: $build_gui_user
- RDP password: $build_gui_password
- Prepared desktop folder: C:\\Users\\Public\\Desktop\\ObjcMarkdownBuild

Build VM environment probe
$(cat "$build_probe_json")

Clean test VM
- Lease ID: $test_id
- SSH: ssh -i <operator-private-key> -p $test_ssh_port $test_ssh_user@$test_host
- RDP: $test_host:$test_gui_port
- RDP username: $test_gui_user
- RDP password: $test_gui_password
- Prepared desktop folder: C:\\Users\\Public\\Desktop\\ObjcMarkdownValidation

Suggested operator flow
1. Connect to the build VM over RDP if you need to reproduce or rebuild the MSI in an msys2/clang64 environment.
2. Connect to the clean test VM over RDP for manual MSI install validation.
3. On the clean test VM, open the staged Markdown files under sample-markdown after installing the MSI.
4. Keep upgrade testing for a second MSI pair; this VM is otherwise clean and ready for first-install validation.

Automated MSI validation result
$validation_note
EOF
}

refresh_status() {
  local otvm_bin="$1"
  local lease_id="$2"
  local output_path="$3"
  otvm_invoke "$otvm_bin" status "$lease_id" > "$output_path"
}

create_cmd() {
  local msi_path=""
  local portable_zip_path=""
  local source_archive=""
  local ttl_hours=""
  local build_lease_id=""
  local test_lease_id=""
  local remote_root="ObjcMarkdownValidation"
  local otvm_bin ssh_key
  local build_json test_json
  local build_dir test_dir handoff_path
  local validation_note="not run"
  local validation_status=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --msi)
        msi_path="${2:?missing msi path}"
        shift 2
        ;;
      --portable-zip)
        portable_zip_path="${2:?missing portable zip path}"
        shift 2
        ;;
      --source-archive)
        source_archive="${2:?missing source archive path}"
        shift 2
        ;;
      --ttl-hours)
        ttl_hours="${2:?missing ttl hours}"
        shift 2
        ;;
      --build-lease-id)
        build_lease_id="${2:?missing build lease id}"
        shift 2
        ;;
      --test-lease-id)
        test_lease_id="${2:?missing test lease id}"
        shift 2
        ;;
      --remote-root)
        remote_root="${2:?missing remote root}"
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
  require_command ssh
  require_command scp
  otvm_bin="$(resolve_otvm_bin)"
  ssh_key="$(resolve_otvm_private_key)"
  mkdir -p "$LEASE_ROOT/build" "$LEASE_ROOT/test"

  if [[ -z "$msi_path" ]]; then
    msi_path="$(find_latest_msi)"
  fi
  if [[ -z "$msi_path" || ! -f "$msi_path" ]]; then
    echo "ERROR: no MSI found. Pass --msi PATH." >&2
    exit 1
  fi

  if [[ -z "$portable_zip_path" ]]; then
    portable_zip_path="$(find_latest_portable_zip)"
  fi
  if [[ -n "$portable_zip_path" && ! -f "$portable_zip_path" ]]; then
    echo "ERROR: portable ZIP not found: $portable_zip_path" >&2
    exit 1
  fi

  if [[ -z "$source_archive" ]]; then
    source_archive="$(make_source_archive "$(mktemp -u "$ROOT/dist/otvm/windows/source-XXXXXX.zip")")"
  fi
  if [[ ! -f "$source_archive" ]]; then
    echo "ERROR: source archive not found: $source_archive" >&2
    exit 1
  fi

  if [[ -z "$build_lease_id" ]]; then
    build_json="$(mktemp)"
    if [[ -n "$ttl_hours" ]]; then
      otvm_invoke "$otvm_bin" create windows-2022 --progress human --ttl-hours "$ttl_hours" --idempotency-key "objcmarkdown-windows-build-$(date -u +%Y%m%d%H%M%S)" --metadata app=ObjcMarkdown --metadata purpose=msi-build --metadata role=build > "$build_json"
    else
      otvm_invoke "$otvm_bin" create windows-2022 --progress human --idempotency-key "objcmarkdown-windows-build-$(date -u +%Y%m%d%H%M%S)" --metadata app=ObjcMarkdown --metadata purpose=msi-build --metadata role=build > "$build_json"
    fi
    build_lease_id="$(json_field '.lease.lease_id' "$build_json")"
  else
    build_json="$(mktemp)"
    refresh_status "$otvm_bin" "$build_lease_id" "$build_json"
  fi

  if [[ -z "$test_lease_id" ]]; then
    test_json="$(mktemp)"
    if [[ -n "$ttl_hours" ]]; then
      otvm_invoke "$otvm_bin" create windows-2022 --progress human --ttl-hours "$ttl_hours" --idempotency-key "objcmarkdown-windows-test-$(date -u +%Y%m%d%H%M%S)" --metadata app=ObjcMarkdown --metadata purpose=msi-validation --metadata role=test > "$test_json"
    else
      otvm_invoke "$otvm_bin" create windows-2022 --progress human --idempotency-key "objcmarkdown-windows-test-$(date -u +%Y%m%d%H%M%S)" --metadata app=ObjcMarkdown --metadata purpose=msi-validation --metadata role=test > "$test_json"
    fi
    test_lease_id="$(json_field '.lease.lease_id' "$test_json")"
  else
    test_json="$(mktemp)"
    refresh_status "$otvm_bin" "$test_lease_id" "$test_json"
  fi

  if [[ "$(json_field '.lease.status' "$build_json")" != "ready" ]]; then
    echo "ERROR: build lease is not ready: $build_lease_id" >&2
    cat "$build_json" >&2
    exit 1
  fi
  if [[ "$(json_field '.lease.status' "$test_json")" != "ready" ]]; then
    echo "ERROR: test lease is not ready: $test_lease_id" >&2
    cat "$test_json" >&2
    exit 1
  fi

  build_dir="$LEASE_ROOT/build/$build_lease_id"
  test_dir="$LEASE_ROOT/test/$test_lease_id"
  mkdir -p "$build_dir" "$test_dir"
  cp -a "$build_json" "$build_dir/lease.json"
  cp -a "$test_json" "$test_dir/lease.json"

  rm -rf "$build_dir/upload" "$test_dir/upload"
  build_build_bundle "$build_dir/upload" "$source_archive"
  build_test_bundle "$test_dir/upload" "$msi_path" "$portable_zip_path"
  zip_bundle "$build_dir/upload" "$build_dir/${remote_root}-build.zip"
  zip_bundle "$test_dir/upload" "$test_dir/${remote_root}-test.zip"

  windows_upload_zip "$build_json" "$build_dir/${remote_root}-build.zip" "$ssh_key" "$(basename "$build_dir/${remote_root}-build.zip")"
  windows_upload_zip "$test_json" "$test_dir/${remote_root}-test.zip" "$ssh_key" "$(basename "$test_dir/${remote_root}-test.zip")"

  run_windows_probe "$build_json" "$ssh_key" "$build_dir/probe.json"
  if run_remote_validation "$test_json" "$ssh_key" "$test_dir" "$(basename "$msi_path")"; then
    validation_note="passed"
  else
    validation_status=$?
    validation_note="failed (exit $validation_status); see $test_dir/logs/"
  fi

  handoff_path="$LEASE_ROOT/handoff.txt"
  write_handoff_file "$build_json" "$test_json" "$build_dir/probe.json" "$validation_note" "$handoff_path"

  cat <<EOF
Created Windows OracleTestVMs leases.
Build lease: $build_lease_id
Test lease: $test_lease_id
Build lease JSON: $build_dir/lease.json
Test lease JSON: $test_dir/lease.json
Handoff: $handoff_path
Automated MSI validation: $validation_note
EOF
}

destroy_cmd() {
  local build_lease_id=""
  local test_lease_id=""
  local otvm_bin

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --build-lease-id)
        build_lease_id="${2:?missing build lease id}"
        shift 2
        ;;
      --test-lease-id)
        test_lease_id="${2:?missing test lease id}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "ERROR: unknown destroy option: $1" >&2
        exit 1
        ;;
    esac
  done

  otvm_bin="$(resolve_otvm_bin)"
  if [[ -n "$build_lease_id" ]]; then
    otvm_invoke "$otvm_bin" destroy "$build_lease_id"
  fi
  if [[ -n "$test_lease_id" ]]; then
    otvm_invoke "$otvm_bin" destroy "$test_lease_id"
  fi
}

status_cmd() {
  local build_lease_id=""
  local test_lease_id=""
  local otvm_bin

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --build-lease-id)
        build_lease_id="${2:?missing build lease id}"
        shift 2
        ;;
      --test-lease-id)
        test_lease_id="${2:?missing test lease id}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "ERROR: unknown status option: $1" >&2
        exit 1
        ;;
    esac
  done

  otvm_bin="$(resolve_otvm_bin)"
  if [[ -n "$build_lease_id" ]]; then
    otvm_invoke "$otvm_bin" status "$build_lease_id"
  fi
  if [[ -n "$test_lease_id" ]]; then
    otvm_invoke "$otvm_bin" status "$test_lease_id"
  fi
}

main() {
  if [[ $# -lt 1 ]]; then
    usage >&2
    exit 1
  fi
  local command="$1"
  shift
  case "$command" in
    create) create_cmd "$@" ;;
    destroy) destroy_cmd "$@" ;;
    status) status_cmd "$@" ;;
    -h|--help) usage ;;
    *)
      echo "ERROR: unknown command: $command" >&2
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"

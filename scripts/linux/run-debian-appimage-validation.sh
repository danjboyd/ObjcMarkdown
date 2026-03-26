#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIST_DIR="$ROOT/dist/linux-validation"
MEDIA_DIR="$DIST_DIR/media"
MEDIA_ROOT="$MEDIA_DIR/root"
MEDIA_ISO_DEFAULT="$MEDIA_DIR/objcmarkdown-validation.iso"
LIVE_ISO_DEFAULT="$HOME/Downloads/debian-live-13.4.0-amd64-gnome.iso"
BASE_IMAGE_DEFAULT="$DIST_DIR/vms/debian13-base.qcow2"
CONNECT_URI_DEFAULT="${OMD_LIBVIRT_URI:-qemu:///session}"
VALIDATION_LABEL="OBJCMD_VALIDATION"

usage() {
  cat <<EOF
usage: $0 <command> [options]

commands:
  create-media   Build an ISO containing the AppImage and guest validation helpers.
  boot-live      Boot the Debian live ISO with the validation ISO attached.
  create-base    Boot the Debian ISO with a writable qcow2 disk for manual install.
  boot-overlay   Boot a disposable overlay qcow2 on top of an installed base image.
  guest-help     Print the commands to run inside the Debian guest.
EOF
}

find_latest_appimage() {
  find "$ROOT/dist" "$ROOT" -maxdepth 2 -type f \
    \( -name 'ObjcMarkdown-*-linux-x86_64.AppImage' -o -name 'MarkdownViewer-*-x86_64.AppImage' \) \
    2>/dev/null | sort -r | head -n 1
}

require_file() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    echo "ERROR: required path not found: $path" >&2
    exit 1
  fi
}

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $name" >&2
    exit 1
  fi
}

guest_help() {
  cat <<EOF
Inside the Debian guest:

1. Mount or open the validation media labeled $VALIDATION_LABEL.
2. Run:
   bash /run/media/\$USER/$VALIDATION_LABEL/validate-appimage-guest.sh
3. For a visual smoke test plus screenshot:
   bash /run/media/\$USER/$VALIDATION_LABEL/validate-appimage-guest.sh --smoke-gui
EOF
}

create_media() {
  local appimage=""
  local output_iso="$MEDIA_ISO_DEFAULT"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --appimage)
        appimage="${2:?missing appimage path}"
        shift 2
        ;;
      --output-iso)
        output_iso="${2:?missing output iso path}"
        shift 2
        ;;
      -h|--help)
        cat <<EOF
usage: $0 create-media [--appimage PATH] [--output-iso PATH]
EOF
        return 0
        ;;
      *)
        echo "ERROR: unknown create-media option: $1" >&2
        return 1
        ;;
    esac
  done

  require_command genisoimage
  mkdir -p "$(dirname "$output_iso")" "$MEDIA_ROOT"

  if [[ -z "$appimage" ]]; then
    appimage="$(find_latest_appimage)"
  fi
  if [[ -z "$appimage" ]]; then
    echo "ERROR: no AppImage found. Pass --appimage or build one first." >&2
    exit 1
  fi
  require_file "$appimage"

  rm -rf "$MEDIA_ROOT"
  mkdir -p "$MEDIA_ROOT"

  cp -a "$appimage" "$MEDIA_ROOT/"
  cp -a "$ROOT/scripts/linux/validate-appimage.sh" "$MEDIA_ROOT/"
  cp -a "$ROOT/scripts/linux/validate-appimage-guest.sh" "$MEDIA_ROOT/"

  cat > "$MEDIA_ROOT/README.txt" <<EOF
ObjcMarkdown Debian validation media

This disc contains:
- $(basename "$appimage")
- validate-appimage.sh
- validate-appimage-guest.sh

Inside the guest, run:
  bash /run/media/\$USER/$VALIDATION_LABEL/validate-appimage-guest.sh

For a GUI smoke test plus screenshot:
  bash /run/media/\$USER/$VALIDATION_LABEL/validate-appimage-guest.sh --smoke-gui
EOF

  (
    cd "$MEDIA_ROOT"
    find . -maxdepth 1 -type f ! -name 'SHA256SUMS' -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
  )

  genisoimage -quiet -V "$VALIDATION_LABEL" -o "$output_iso" -J -R "$MEDIA_ROOT"
  echo "Created validation ISO: $output_iso"
}

build_live_args() {
  local live_iso="$1"
  local validation_iso="$2"
  local name="$3"
  local connect_uri="$4"
  local memory="$5"
  local vcpus="$6"
  local dry_run="$7"

  local args=(
    --connect "$connect_uri"
    --name "$name"
    --memory "$memory"
    --vcpus "$vcpus"
    --cpu host-passthrough
    --virt-type kvm
    --osinfo debian13
    --cdrom "$live_iso"
    --disk "path=$validation_iso,device=cdrom,readonly=on"
    --network "type=user,model=virtio"
    --graphics spice
    --video virtio
    --sound none
    --input tablet,bus=usb
    --boot menu=on
    --wait 0
  )

  if [[ "$dry_run" -eq 1 ]]; then
    args+=(--dry-run --noautoconsole)
  elif [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    args+=(--autoconsole graphical)
  else
    args+=(--noautoconsole)
  fi

  printf '%s\n' "${args[@]}"
}

boot_live() {
  local live_iso="$LIVE_ISO_DEFAULT"
  local validation_iso="$MEDIA_ISO_DEFAULT"
  local name="omd-debian-live-smoke"
  local connect_uri="$CONNECT_URI_DEFAULT"
  local memory="8192"
  local vcpus="4"
  local dry_run=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --live-iso)
        live_iso="${2:?missing live iso path}"
        shift 2
        ;;
      --validation-iso)
        validation_iso="${2:?missing validation iso path}"
        shift 2
        ;;
      --name)
        name="${2:?missing vm name}"
        shift 2
        ;;
      --connect)
        connect_uri="${2:?missing libvirt uri}"
        shift 2
        ;;
      --memory)
        memory="${2:?missing memory}"
        shift 2
        ;;
      --vcpus)
        vcpus="${2:?missing vcpus}"
        shift 2
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      -h|--help)
        cat <<EOF
usage: $0 boot-live [--live-iso PATH] [--validation-iso PATH] [--name NAME] [--memory MiB] [--vcpus N] [--connect URI] [--dry-run]
EOF
        return 0
        ;;
      *)
        echo "ERROR: unknown boot-live option: $1" >&2
        return 1
        ;;
    esac
  done

  require_command virt-install
  require_file "$live_iso"
  if [[ ! -f "$validation_iso" ]]; then
    create_media --output-iso "$validation_iso"
  fi

  mapfile -t args < <(build_live_args "$live_iso" "$validation_iso" "$name" "$connect_uri" "$memory" "$vcpus" "$dry_run")

  echo "Booting live validation VM: $name"
  echo "Validation ISO: $validation_iso"
  guest_help
  virt-install "${args[@]}"
}

create_base() {
  local live_iso="$LIVE_ISO_DEFAULT"
  local validation_iso="$MEDIA_ISO_DEFAULT"
  local base_image="$BASE_IMAGE_DEFAULT"
  local name="omd-debian-base-install"
  local connect_uri="$CONNECT_URI_DEFAULT"
  local memory="8192"
  local vcpus="4"
  local disk_size="40"
  local dry_run=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --live-iso)
        live_iso="${2:?missing live iso path}"
        shift 2
        ;;
      --validation-iso)
        validation_iso="${2:?missing validation iso path}"
        shift 2
        ;;
      --base-image)
        base_image="${2:?missing base image path}"
        shift 2
        ;;
      --name)
        name="${2:?missing vm name}"
        shift 2
        ;;
      --connect)
        connect_uri="${2:?missing libvirt uri}"
        shift 2
        ;;
      --memory)
        memory="${2:?missing memory}"
        shift 2
        ;;
      --vcpus)
        vcpus="${2:?missing vcpus}"
        shift 2
        ;;
      --disk-size)
        disk_size="${2:?missing disk size}"
        shift 2
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      -h|--help)
        cat <<EOF
usage: $0 create-base [--live-iso PATH] [--validation-iso PATH] [--base-image PATH] [--disk-size GiB] [--memory MiB] [--vcpus N] [--connect URI] [--dry-run]
EOF
        return 0
        ;;
      *)
        echo "ERROR: unknown create-base option: $1" >&2
        return 1
        ;;
    esac
  done

  require_command virt-install
  require_file "$live_iso"
  if [[ ! -f "$validation_iso" ]]; then
    create_media --output-iso "$validation_iso"
  fi

  mkdir -p "$(dirname "$base_image")"
  if [[ ! -f "$base_image" && "$dry_run" -ne 1 ]]; then
    qemu-img create -f qcow2 "$base_image" "${disk_size}G" >/dev/null
  fi

  local base_disk_arg=""
  if [[ -f "$base_image" ]]; then
    base_disk_arg="path=$base_image,format=qcow2,bus=virtio"
  else
    base_disk_arg="path=$base_image,size=$disk_size,format=qcow2,bus=virtio"
  fi

  local args=(
    --connect "$connect_uri"
    --name "$name"
    --memory "$memory"
    --vcpus "$vcpus"
    --cpu host-passthrough
    --virt-type kvm
    --osinfo debian13
    --cdrom "$live_iso"
    --disk "$base_disk_arg"
    --disk "path=$validation_iso,device=cdrom,readonly=on"
    --network "type=user,model=virtio"
    --graphics spice
    --video virtio
    --sound none
    --input tablet,bus=usb
    --boot menu=on
  )

  if [[ "$dry_run" -eq 1 ]]; then
    args+=(--dry-run --noautoconsole)
  elif [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    args+=(--autoconsole graphical)
  else
    args+=(--noautoconsole)
  fi

  cat <<EOF
Launching Debian base install VM: $name
Base image: $base_image

After installing Debian into this disk, power the VM off cleanly and keep
$base_image as the read-only source for overlay validation runs.

Recommended one-time guest prep before sealing the base:
- install openssh-server if you want SSH-based overlay automation later
- ensure the desktop auto-login/preferences are in the state you want to test
EOF

  virt-install "${args[@]}"
}

boot_overlay() {
  local base_image="$BASE_IMAGE_DEFAULT"
  local validation_iso="$MEDIA_ISO_DEFAULT"
  local name="omd-debian-overlay-smoke"
  local overlay_image=""
  local connect_uri="$CONNECT_URI_DEFAULT"
  local memory="8192"
  local vcpus="4"
  local ssh_forward_port="2222"
  local dry_run=0
  local replace_overlay=0
  local cleanup_overlay=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base-image)
        base_image="${2:?missing base image path}"
        shift 2
        ;;
      --validation-iso)
        validation_iso="${2:?missing validation iso path}"
        shift 2
        ;;
      --overlay-image)
        overlay_image="${2:?missing overlay image path}"
        shift 2
        ;;
      --name)
        name="${2:?missing vm name}"
        shift 2
        ;;
      --connect)
        connect_uri="${2:?missing libvirt uri}"
        shift 2
        ;;
      --memory)
        memory="${2:?missing memory}"
        shift 2
        ;;
      --vcpus)
        vcpus="${2:?missing vcpus}"
        shift 2
        ;;
      --ssh-forward-port)
        ssh_forward_port="${2:?missing ssh forward port}"
        shift 2
        ;;
      --replace-overlay)
        replace_overlay=1
        shift
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      -h|--help)
        cat <<EOF
usage: $0 boot-overlay [--base-image PATH] [--validation-iso PATH] [--overlay-image PATH] [--name NAME] [--memory MiB] [--vcpus N] [--ssh-forward-port PORT] [--replace-overlay] [--connect URI] [--dry-run]
EOF
        return 0
        ;;
      *)
        echo "ERROR: unknown boot-overlay option: $1" >&2
        return 1
        ;;
    esac
  done

  require_command virt-install
  require_file "$base_image"
  if [[ ! -f "$validation_iso" ]]; then
    create_media --output-iso "$validation_iso"
  fi

  if [[ -z "$overlay_image" ]]; then
    overlay_image="$DIST_DIR/overlays/$name.qcow2"
  fi
  mkdir -p "$(dirname "$overlay_image")"

  if [[ -f "$overlay_image" && "$replace_overlay" -ne 1 && "$dry_run" -ne 1 ]]; then
    echo "ERROR: overlay image already exists: $overlay_image" >&2
    echo "Pass --replace-overlay to recreate it." >&2
    exit 1
  fi

  if [[ "$dry_run" -ne 1 ]]; then
    if [[ -f "$overlay_image" && "$replace_overlay" -eq 1 ]]; then
      rm -f "$overlay_image"
    fi
    qemu-img create -f qcow2 -F qcow2 -b "$base_image" "$overlay_image" >/dev/null
  elif [[ ! -f "$overlay_image" ]]; then
    qemu-img create -f qcow2 -F qcow2 -b "$base_image" "$overlay_image" >/dev/null
    cleanup_overlay=1
  fi

  local args=(
    --connect "$connect_uri"
    --name "$name"
    --memory "$memory"
    --vcpus "$vcpus"
    --cpu host-passthrough
    --virt-type kvm
    --osinfo debian13
    --import
    --disk "path=$overlay_image,format=qcow2,bus=virtio"
    --disk "path=$validation_iso,device=cdrom,readonly=on"
    --network "type=user,model=virtio,portForward0.proto=tcp,portForward0.range0.start=$ssh_forward_port,portForward0.range0.to=22"
    --graphics spice
    --video virtio
    --sound none
    --input tablet,bus=usb
    --transient
    --destroy-on-exit
    --wait 0
  )

  if [[ "$dry_run" -eq 1 ]]; then
    args+=(--dry-run --noautoconsole)
  elif [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    args+=(--autoconsole graphical)
  else
    args+=(--noautoconsole)
  fi

  cat <<EOF
Booting disposable Debian overlay VM: $name
Base image:    $base_image
Overlay image: $overlay_image
Validation ISO: $validation_iso

If the base guest has OpenSSH enabled, the host-side SSH path will be:
  ssh -p $ssh_forward_port <guest-user>@127.0.0.1
EOF
  guest_help

  virt-install "${args[@]}"

  if [[ "$cleanup_overlay" -eq 1 ]]; then
    rm -f "$overlay_image"
  fi
}

main() {
  local command="${1:-}"
  if [[ -z "$command" ]]; then
    usage >&2
    exit 1
  fi
  shift

  case "$command" in
    create-media)
      create_media "$@"
      ;;
    boot-live)
      boot_live "$@"
      ;;
    create-base)
      create_base "$@"
      ;;
    boot-overlay)
      boot_overlay "$@"
      ;;
    guest-help)
      guest_help
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "ERROR: unknown command: $command" >&2
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"

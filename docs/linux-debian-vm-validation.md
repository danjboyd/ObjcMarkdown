# Local Debian VM Validation

For Linux clean-machine validation, the preferred local path is a disposable Debian VM under `qemu/kvm`, not the long-lived host workstation and not a container.

For `Phase 9C`, the preferred cloud handoff path is now `OracleTestVMs` with
the `debian-13-gnome-wayland` profile. The local libvirt flow below remains
useful when OCI access is unavailable or when you want a purely local smoke
environment.

## OracleTestVMs Preferred Flow

Use the repo-owned helper:

```bash
./scripts/linux/otvm-appimage-validation.sh create
```

That flow:

- creates a fresh Debian 13 GNOME Wayland lease through `OracleTestVMs`
- uploads the latest built `ObjcMarkdown` AppImage
- uploads a small set of sample Markdown documents:
  - `Resources/sample-commonmark.md`
  - `InlineStyleDemo.md`
  - `TableRenderDemo.md`
  - `README.md`
- writes handoff instructions to `dist/otvm/linux/<lease-id>/handoff.txt`

The handoff includes:

- SSH connection command
- RDP host, username, and password
- the guest payload directory under `/home/tester/ObjcMarkdownValidation`

Destroy a finished lease with:

```bash
./scripts/linux/otvm-appimage-validation.sh destroy <lease-id>
```

## Practical Approach

Two levels are useful:

- quick visual smoke test: boot a Debian live ISO and attach validation media containing the AppImage
- repeatable release validation: install Debian once into a qcow2 base image, then boot a fresh overlay qcow2 for every test run

The live ISO is good for answering "does this AppImage launch on a clean Debian desktop?" quickly. The installed base plus overlays is the better long-term release-validation path.

## Host-Side Scripts

- [run-debian-appimage-validation.sh](../scripts/linux/run-debian-appimage-validation.sh)
- [validate-appimage-guest.sh](../scripts/linux/validate-appimage-guest.sh)
- [validate-appimage.sh](../scripts/linux/validate-appimage.sh)

`run-debian-appimage-validation.sh` supports four main flows:

1. `create-media`
   Builds `dist/linux-validation/media/objcmarkdown-validation.iso` containing the AppImage plus guest helper scripts.
2. `boot-live`
   Boots a disposable Debian live session with that validation ISO attached.
3. `create-base`
   Boots the Debian ISO with a writable qcow2 disk so you can install Debian once.
4. `boot-overlay`
   Boots a transient overlay qcow2 on top of the installed base image and forwards host TCP port `2222` to guest port `22`.

## Current Defaults

The script defaults match this machine:

- libvirt URI: `qemu:///session`
- live ISO: `~/Downloads/debian-live-13.4.0-amd64-gnome.iso`
- base image path: `dist/linux-validation/vms/debian13-base.qcow2`

## Quick Live Smoke Test

Create validation media:

```bash
./scripts/linux/run-debian-appimage-validation.sh create-media
```

Boot the live ISO:

```bash
./scripts/linux/run-debian-appimage-validation.sh boot-live
```

Inside the guest, run:

```bash
bash /run/media/$USER/OBJCMD_VALIDATION/validate-appimage-guest.sh --smoke-gui
```

That performs the repo-side packaged runtime inspection pass, then launches the AppImage briefly and captures a screenshot when a guest screenshot tool is available.

## Repeatable Overlay Flow

Create the base install VM once:

```bash
./scripts/linux/run-debian-appimage-validation.sh create-base
```

After installing Debian into the base disk, recommended one-time guest prep is:

- install `openssh-server` if you want host-side SSH access into overlay guests
- confirm the desktop environment and display settings match the release-validation target
- shut the VM down cleanly and keep the base qcow2 unchanged afterward

Then launch a disposable overlay for each run:

```bash
./scripts/linux/run-debian-appimage-validation.sh boot-overlay
```

If the base guest has SSH enabled, the guest will be reachable from the host at:

```bash
ssh -p 2222 <guest-user>@127.0.0.1
```

Inside the guest, run the same `validate-appimage-guest.sh` helper from the mounted validation media.

# Linux AppImage Handoff (2026-03-26)

This note captures the Linux packaging state at the end of the March 26, 2026 session.

## Landed Work

- Added tagged-release Linux AppImage workflow:
  - `.github/workflows/linux-appimage.yml`
- Added Linux packaging and validation scripts:
  - `scripts/linux/stage-appimage-runtime.sh`
  - `scripts/linux/validate-appimage.sh`
  - `scripts/linux/validate-appimage-guest.sh`
  - `scripts/linux/run-debian-appimage-validation.sh`
- Added public docs:
  - `docs/linux-appimage-packaging.md`
  - `docs/linux-debian-vm-validation.md`
- Updated `README.md` with Linux AppImage release flow.

## What Works

- Host-side `gmake` and GNUstep `xctest ObjcMarkdownTests/ObjcMarkdownTests.bundle` passed.
- Local AppDir validation passes.
- Local AppImage validation passes.
- The packaged runtime now includes:
  - project shared libraries
  - GNUstep libraries, bundles, color pickers, and `defaults`
  - copied fontconfig and GLib schemas
  - bundled `Adwaita.theme`
- The generated launcher now:
  - seeds `GSTheme=Adwaita`
  - sanitizes host GNUstep paths out of `PATH` and `LD_LIBRARY_PATH`
  - writes an AppImage-specific `GNUSTEP_CONFIG_FILE`
- Host-side backend debug for the AppImage succeeds:

```text
Loading Backend from /tmp/.mount_.../usr/GNUstep/System/Library/Bundles/libgnustep-back-032.bundle
```

That proves the current host artifact is no longer falling back to `/usr/GNUstep`.

## Clean Debian Status

- Validation target:
  - Debian live ISO: `~/Downloads/debian-live-13.4.0-amd64-gnome.iso`
  - libvirt domain: `omd-debian-live-smoke`
  - libvirt URI: `qemu:///session`
- Validation media:
  - `dist/linux-validation/media/objcmarkdown-validation.iso`
- Current AppImage:
  - `dist/ObjcMarkdown-0.0.0-dev-linux-x86_64.AppImage`
  - SHA-256: `77e2692d52c0253f266b77e7a0d4ef8dd273c15ef4223919dc6877575c783374`
- The validation ISO was verified to contain the same AppImage hash as the host copy.

## Current Blocker

On the clean Debian live guest, the packaged-runtime validator passes, but the GUI launch still fails with:

```text
Did not find correct version of backend (libgnustep-back-032.bundle), falling back to std (libgnustep-back.bundle).
NSApplication.m:306  Assertion failed in BOOL initialize_gnustep_backend(void).  Unable to find backend back
```

This still reproduces in the guest with:

```bash
APPIMAGE_EXTRACT_AND_RUN=1 /run/user/1000/objcmarkdown-validation/ObjcMarkdown-0.0.0-dev-linux-x86_64.AppImage --GNU-Debug=BackendBundle
```

Notably, the guest output above does **not** show the extra `GNU-Debug=BackendBundle` path diagnostics that appear on the host, so the next session should treat the guest as the source of truth and inspect the guest-side extracted payload directly.

## Strongest Evidence So Far

1. The old `/usr/GNUstep` fallback problem was real and is fixed on the host.
2. The AppImage inside the ISO is current, not stale.
3. The remaining failure is clean-machine-specific.
4. The most likely remaining causes are:
   - a backend dependency still missing on Debian live but present on the host
   - a guest-side mismatch between the generated runtime config and what GNUstep actually consumes there

## First Commands To Run Next Session

Inside the Debian guest:

```bash
cd /run/user/1000/objcmarkdown-validation
rm -rf squashfs-root
./ObjcMarkdown-0.0.0-dev-linux-x86_64.AppImage --appimage-extract >/dev/null
LD_LIBRARY_PATH="$PWD/squashfs-root/usr/lib:$PWD/squashfs-root/usr/GNUstep/System/Library/Libraries" \
ldd "$PWD/squashfs-root/usr/GNUstep/System/Library/Bundles/libgnustep-back-032.bundle/libgnustep-back-032"
```

Then inspect:

```bash
cat "$HOME/.config/objcmarkdown-appimage/GNUstep/Runtime/GNUstep.conf"
find /run/user/1000/objcmarkdown-validation/squashfs-root/usr/GNUstep/System/Library/Bundles -maxdepth 2 -type f
```

If the live session keeps being awkward, the better follow-on is to create the installed Debian base VM and use overlay boots plus SSH instead of continuing to debug in the live desktop.

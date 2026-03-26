# Linux AppImage Packaging

`ObjcMarkdown` now has a release-oriented Linux packaging lane that mirrors the Windows MSI workflow: build the app on the supported toolchain, stage a self-contained runtime, then publish a tagged artifact.

## Goals

- Use the same self-hosted clang/libobjc2/libdispatch GNUstep environment as the main Linux CI lane.
- Bundle the GNUstep runtime used by this project instead of relying on distro GNUstep packages.
- Bundle the `Adwaita.theme` GNUstep theme and make it the packaged default theme.
- Emit a release artifact on `v*` tags in GitHub Actions.

## Workflow

The GitHub Actions entry point is:

- [linux-appimage.yml](../.github/workflows/linux-appimage.yml)

That workflow:

1. Checks out this repo and the pinned `plugins-themes-Adwaita` source tree.
2. Builds `ObjcMarkdown` in the canonical Linux GNUstep clang environment.
3. Runs [scripts/linux/stage-appimage-runtime.sh](../scripts/linux/stage-appimage-runtime.sh) to assemble `dist/ObjcMarkdown.AppDir`.
4. Runs [scripts/linux/validate-appimage.sh](../scripts/linux/validate-appimage.sh) against the staged AppDir.
5. Uses `linuxdeploy` plus the AppImage plugin to produce `ObjcMarkdown-<version>-linux-x86_64.AppImage`.
6. Validates the generated AppImage with the same wrapper diagnostic.

## Staged Runtime

The staging script creates an AppDir with:

- `MarkdownViewer.app`
- project shared libraries (`ObjcMarkdown`, `OpenSave`, `TextViewVimKit`)
- bundled GNUstep libraries, bundles, color pickers, makefiles, and the `defaults` tool
- copied fontconfig and GLib schema data used by the GTK-backed GNUstep runtime
- the Adwaita GNUstep theme installed under the staged GNUstep `Themes` directory
- a launcher wrapper that seeds `GSTheme=Adwaita` and writes that default into the AppImage-specific GNUstep defaults domain when no explicit override exists

## Theme Input

The workflow treats the Adwaita theme as an explicit packaging input:

- Repository: `danjboyd/plugins-themes-Adwaita`
- Pinned ref: `9d455f67587242400f6620a0e8884084850d1204`

Update the workflow env if you want to move the packaged theme to a newer commit or tag.

## Local Dry Run

On a Linux machine with the supported GNUstep clang stack:

```bash
set +u
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
set -u
gmake OMD_SKIP_TESTS=1
./scripts/linux/stage-appimage-runtime.sh dist/ObjcMarkdown.AppDir /path/to/plugins-themes-Adwaita
./scripts/linux/validate-appimage.sh dist/ObjcMarkdown.AppDir
```

The validation script runs the launcher in diagnostic mode and checks that the staged runtime, backend bundle, defaults tool, and Adwaita theme are all visible from the packaged environment.

## Clean Debian Validation

For local clean-machine testing on this project, use a disposable Debian VM under `qemu/kvm` rather than relying on the host workstation state.

The local runbook is:

- [linux-debian-vm-validation.md](linux-debian-vm-validation.md)

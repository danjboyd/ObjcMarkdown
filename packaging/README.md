# Packaging

Phase 8 externalizes backend packaging through `gnustep-packager`.

This repo now owns only:

- build commands
- normalized stage scripts
- downstream manifests
- update-feed metadata and publication policy
- app-specific packaging input preflight only where `gnustep-packager` does not yet provide a backend-owned input mechanism
- libvirt-first `OracleTestVMs` clean-machine validation hooks
- OracleTestVMs validation handoff scripts

`gnustep-packager` owns the installer/AppImage backends, package transforms,
launcher generation, package validation, and reusable GitHub Actions entry
point. Its hosted workflows bootstrap and smoke-test the GNUstep toolchain
through `gnustep-cli-new` before running this repo's build and stage commands.
ObjcMarkdown should not carry release-workflow steps that directly install the
default GNUstep toolchain on hosted runners.

Current manifests:

- `packaging/manifests/linux-appimage.manifest.json`
- `packaging/manifests/windows-msi.manifest.json`

Pinned external packaging inputs:

- `packaging/inputs.json`

Those inputs are intentionally tracked as external packaging workspace
dependencies rather than git submodules. Windows GNUstep theme inputs are
declared through `gnustep-packager` `themeInputs` so the packager owns
fetch/build/install/stage/validation. The main app repo should stay light for
normal development, while release packaging can materialize the exact external
repos it needs at pinned commits.

## Update Policy

`Phase 9A` enables shared update metadata in both manifests through
`gnustep-packager`:

- AppImage uses GitHub Releases for the actual `.AppImage` and `.zsync`
  artifacts plus a stable GitHub Pages feed URL at
  `https://danjboyd.github.io/ObjcMarkdown/updates/linux/stable.json`.
- Windows MSI uses GitHub Releases for the signed `.msi` artifact plus a stable
  GitHub Pages feed URL at
  `https://danjboyd.github.io/ObjcMarkdown/updates/windows/stable.json`.
- Windows packaging continues to use the MSYS2 `clang64` toolchain and the
  stable `UpgradeCode` already recorded in the manifest.
- AppImage updates rely on native AppImage update metadata and the generated
  `.zsync` sidecar rather than repo-local update logic.
- MSI upgrades rely on the existing `UpgradeCode`, numeric MSI version
  normalization inside `gnustep-packager`, and a new signed installer published
  for each release.

For the full policy and release invariants, see
`docs/auto-update-policy.md`.

## Local Linux AppImage

On the supported GNUstep/Linux host:

```bash
scripts/ci/run-linux-ci.sh
pwsh ../gnustep/gnustep-packager/scripts/run-packaging-pipeline.ps1 \
  -Manifest packaging/manifests/linux-appimage.manifest.json \
  -Backend appimage \
  -RunSmoke
./scripts/linux/validate-appimage.sh dist/packaging/linux/packages/ObjcMarkdown-0.1.1-rc2-linux-x86_64.AppImage
```

If you want a version override, pass `-PackageVersion 0.1.1-rc2` to the
packager pipeline.

When updates are enabled, the Linux package output should also include:

- `.AppImage.zsync`
- `.update-feed.json`

Linux packaging input expectations:

- `plugins-themes-adwaita` should be present in the sibling packaging workspace
  at the pinned commit chosen for the release until `gnustep-packager` supports
  AppImage theme provisioning.
- Hosted release packaging lets the reusable `gnustep-packager` workflow
  provision and verify the GNUstep toolchain through `gnustep-cli-new`; the
  ObjcMarkdown preflight only prepares app-specific inputs such as the Adwaita
  theme checkout.

## Local Windows MSI

From Windows PowerShell with MSYS2 `clang64` installed:

```powershell
pwsh ..\gnustep-packager\scripts\run-packaging-pipeline.ps1 `
  -Manifest packaging\manifests\windows-msi.manifest.json `
  -Backend msi `
  -RunSmoke
```

For the tracked clean-machine validation loop, use the OracleTestVMs helper:

```bash
./scripts/windows/otvm-msi-validation.sh create \
  --msi dist/packaging/windows/packages/ObjcMarkdown-0.1.1-rc2-win64.msi \
  --portable-zip dist/packaging/windows/packages/ObjcMarkdown-0.1.1-rc2-win64-portable.zip
```

When updates are enabled, the Windows package output should also include:

- `.update-feed.json`

Windows packaging input expectations:

- the staged/installable runtime must include `WinUITheme`
- the packaged Windows default theme must be `WinUITheme`
- `plugins-themes-winuitheme` should be declared as a required/default
  `themeInputs` entry in the Windows MSI manifest
- optional secondary themes such as `Win11Theme` should also be manifest
  `themeInputs` entries, not submodules
- hosted release packaging lets the reusable `gnustep-packager` workflow
  provision and verify the MSYS2/GNUstep toolchain through `gnustep-cli-new`

If a Windows build VM cannot compile `plugins-themes-winuitheme` cleanly, treat
that as a packager/toolchain/theme-input issue first, not as a reason to convert
the app repo to submodules or permanent repo-local theme build scripts.

## OracleTestVMs Linux Validation

For the Phase 9C Linux handoff path, use:

```bash
./scripts/linux/otvm-appimage-validation.sh create
```

That script:

- creates a fresh `debian-13-gnome-wayland` lease through `OracleTestVMs`
- expects `OracleTestVMs` to be configured for libvirt-backed Debian leases going forward
- uploads the latest built AppImage
- uploads a small validation document set
- writes a handoff file under `dist/otvm/linux/<lease-id>/handoff.txt`

Destroy a finished lease with:

```bash
./scripts/linux/otvm-appimage-validation.sh destroy <lease-id>
```

## OracleTestVMs Windows Validation

For the Phase 9D and 9E Windows handoff path, use:

```bash
./scripts/windows/otvm-msi-validation.sh create \
  --msi dist/github-run-23612901170/objcmarkdown-windows-0.1.1/ObjcMarkdown-0.1.1.0-win64.msi \
  --portable-zip dist/github-run-23612901170/objcmarkdown-windows-0.1.1/ObjcMarkdown-0.1.1-win64-portable.zip
```

That script:

- creates a separate Windows build lease and Windows clean-test lease through `OracleTestVMs`
- expects `OracleTestVMs` to be configured for libvirt-backed Windows leases going forward
- uploads a source snapshot and build instructions to the build VM
- uploads the MSI, optional portable ZIP, validator, and sample Markdown fixtures to the clean-test VM
- runs unattended MSI install/smoke/uninstall once on the clean-test VM
- writes lease JSON plus a combined handoff file under `dist/otvm/windows/`

Destroy finished Windows leases with:

```bash
./scripts/windows/otvm-msi-validation.sh destroy \
  --build-lease-id <build-lease-id> \
  --test-lease-id <test-lease-id>
```

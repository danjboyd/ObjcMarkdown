# Packaging

Phase 8 externalizes backend packaging through `gnustep-packager`.

This repo now owns only:

- build commands
- normalized stage scripts
- downstream manifests
- update-feed metadata and publication policy
- Linux runner preflight
- OCI clean-machine MSI validation hooks
- OracleTestVMs validation handoff scripts

Current manifests:

- `packaging/manifests/linux-appimage.manifest.json`
- `packaging/manifests/windows-msi.manifest.json`

Pinned external packaging inputs:

- `packaging/inputs.json`

Those inputs are intentionally tracked as external packaging workspace
dependencies rather than git submodules. The main app repo should stay light for
normal development, while release packaging can materialize the exact theme
repos it needs at pinned commits in a sibling workspace.

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
  at the pinned commit chosen for the release.

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

- `plugins-themes-winuitheme`
- `plugins-themes-win11theme`

Those should be fetched into the packaging workspace at pinned commits rather
than added as submodules of this repo. If a Windows build VM cannot compile
those theme repos cleanly, treat that as an environment/toolchain issue first,
not as a reason to convert the app repo to submodules.

## OracleTestVMs Linux Validation

For the Phase 9C Linux handoff path, use:

```bash
./scripts/linux/otvm-appimage-validation.sh create
```

That script:

- creates a fresh `debian-13-gnome-wayland` lease through `OracleTestVMs`
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

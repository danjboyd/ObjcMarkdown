# Auto-Update Policy

This document captures the `Phase 9A` update policy for `ObjcMarkdown` now
that packaging is externalized through `gnustep-packager`.

## Goals

- keep release discovery backend-neutral at the app layer
- use standard update mechanisms for AppImage and MSI rather than repo-local
  patching or self-replacement logic
- publish stable channel feed URLs that the packaged app can consume over time
- preserve upgrade compatibility across releases

## Release Surfaces

`ObjcMarkdown` uses two publication surfaces per release:

- GitHub Releases for downloadable release assets
- GitHub Pages for stable update feed URLs

Stable feed URLs:

- Linux AppImage:
  `https://danjboyd.github.io/ObjcMarkdown/updates/linux/stable.json`
- Windows MSI:
  `https://danjboyd.github.io/ObjcMarkdown/updates/windows/stable.json`

The feeds point at GitHub Release assets for the actual downloads.

## Linux AppImage Policy

Linux updates follow AppImage-native best practices:

- embed standard AppImage update information into the packaged `.AppImage`
- emit and publish the matching `.AppImage.zsync` sidecar
- keep release asset naming stable across tagged releases
- prefer standard AppImage tooling such as `AppImageUpdate`,
  `AppImageLauncher`, and compatible consumers over app-specific replacement
  logic

Manifest invariants:

- `updates.enabled` stays `true`
- `updates.provider` stays `github-release-feed`
- `backends.appimage.updates.feedUrl` points at the stable Linux feed URL
- `backends.appimage.updates.embedUpdateInformation` stays `true`
- `backends.appimage.updates.releaseSelector` remains compatible with the
  published GitHub Release strategy
- `backends.appimage.updates.zsyncArtifactNamePattern` stays aligned with the
  emitted AppImage artifact name

Release invariants:

- publish the `.AppImage`
- publish the `.AppImage.zsync`
- publish the generated `.update-feed.json` to the stable Linux feed URL

## Windows MSI Policy

Windows updates follow MSI upgrade best practices through
`gnustep-packager`:

- keep a stable `UpgradeCode`
- let the backend normalize package versions into MSI-safe numeric versions
- ship a new signed MSI for each released version
- hand upgrade execution off to MSI semantics rather than replacing installed
  binaries in place

Toolchain policy:

- continue to build Windows packages with the MSYS2 `clang64` toolchain
- keep `fallbackRuntimeRoot` aligned with the current `C:\clang64` runtime
  expectation for packaging-time closure resolution
- validate the produced MSI on a clean Windows VM that is separate from the
  build environment

Manifest invariants:

- `updates.enabled` stays `true`
- `updates.provider` stays `github-release-feed`
- `backends.msi.updates.feedUrl` points at the stable Windows feed URL
- `backends.msi.upgradeCode` remains stable across upgrade-compatible releases

Release invariants:

- publish the signed `.msi`
- publish the generated `.update-feed.json` to the stable Windows feed URL
- do not reset the `UpgradeCode` unless intentionally breaking the upgrade path

## Channel Policy

Current channel policy:

- `stable` only

If `beta` or `nightly` channels are introduced later, each channel should get:

- a separate feed URL
- separate GitHub Release publication rules
- no mixed stable/prerelease feed document

## Manual Validation Expectations

Every release candidate should confirm:

- the Linux AppImage package contains embedded update metadata and emits a
  `.zsync` sidecar
- the Linux feed JSON resolves to the same AppImage release assets that users
  download
- the Windows feed JSON resolves to the signed MSI release asset
- the MSI still upgrades cleanly on a clean Windows VM

## Non-Goals

This policy does not add:

- repo-local binary self-replacement logic
- custom Windows patching outside MSI upgrade behavior
- channel inference from free-form GitHub release titles

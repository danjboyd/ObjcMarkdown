# Asset Ownership Boundaries

This file defines which project owns which assets in the ObjcMarkdown release
pipeline. The goal is to keep ObjcMarkdown focused on being a good Markdown GUI
application while `gnustep-packager` owns reusable installer/runtime packaging
mechanics.

## ObjcMarkdown-Owned Assets

ObjcMarkdown owns assets that are part of the application product:

- Markdown renderer resources, including default TOML themes under `Resources/`.
- Viewer UI assets such as app icons and toolbar/open icons.
- Sample or smoke Markdown documents used to validate app behavior.
- App binaries and app-local dynamic libraries produced by this repository.
- App metadata and update policy values declared in packaging manifests.
- App-specific validation expectations that are not generally true for every
  GNUstep app.
- OracleTestVMs handoff scripts and product-specific UAT notes.

ObjcMarkdown stage scripts may copy these assets into the normalized package
layout:

- `app/`
- `runtime/` for app-produced libraries that the app needs
- `metadata/` for app icons, notices, smoke files, and release metadata

## gnustep-packager-Owned Assets

`gnustep-packager` owns assets and transformations that are reusable packaging
infrastructure:

- MSI and AppImage backend implementation.
- Generated launchers and launcher configuration.
- GNUstep runtime closure discovery and package transform logic.
- Hosted runner/toolchain bootstrap through `gnustep-cli-new`.
- Manifest-driven host dependency provisioning.
- Package, installed-result, and smoke validation framework.
- Packaged default seeding such as `packagedDefaults.defaultTheme`.
- Windows/MSI GNUstep theme input provisioning through `themeInputs`.
- Fetching, building, installing, staging, and validating complete `.theme`
  bundles for packager-supported theme backends.
- Theme payload reports such as `metadata/gnustep-packager-theme-report.json`.

For Windows MSI, `WinUITheme` is declared as a required/default `themeInputs`
entry. ObjcMarkdown should not carry permanent repo-local logic to clone, build,
install, or copy `WinUITheme.theme`.

## Current Backend Notes

Windows/MSI:

- `gnustep-packager` owns `WinUITheme` provisioning and structural validation
  through the MSI manifest `themeInputs` entry.
- ObjcMarkdown still owns app-specific validation if we need to assert a
  product-specific file or behavior beyond normal GNUstep theme structure.

Linux/AppImage:

- `gnustep-packager` does not yet provision `themeInputs` for AppImage.
- ObjcMarkdown may keep Linux Adwaita preparation downstream until upstream
  AppImage theme provisioning lands.

## Boundary Rule

If an asset is required because it is part of ObjcMarkdown's product identity or
viewer behavior, keep it in this repository. If an asset is required because a
GNUstep application package needs a runtime, launcher, installer backend, or
third-party GNUstep theme bundle, express the intent in the manifest and prefer
`gnustep-packager` ownership.

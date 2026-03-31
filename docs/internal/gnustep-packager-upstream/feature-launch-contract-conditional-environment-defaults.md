# Feature Request: launch contract should support conditional environment defaults instead of only unconditional overrides

## Summary
The shared launch contract currently renders environment variables as
unconditional assignments in both generated launchers. That is too limited for
real GNUstep apps that want to ship a good default theme or runtime setting
without stomping on user overrides.

## Status
Addressed in the current `gnustep-packager` working tree on `2026-03-31`.

## Evidence
- The architecture doc explicitly calls out "default theme selection" as part of
  the shared launch contract:
  - `docs/architecture.md` lines 63-72
- The AppImage backend currently renders each launch environment entry as an
  unconditional `export`:
  - `backends/appimage/lib/appimage.ps1` lines 836-837
- The MSI launcher currently applies each configured environment entry through
  unconditional `SetEnvironmentVariableW` calls:
  - `backends/msi/assets/GpWindowsLauncher.c` lines 551-563

## Downstream impact
`ObjcMarkdown` wants to ship:

- Adwaita as the default GNUstep theme on Linux AppImage builds
- WinUXTheme as the default GNUstep theme on Windows MSI builds

But its current internal launchers do that only when the user has not already
chosen something else:

- Linux AppImage launcher:
  - `scripts/linux/stage-appimage-runtime.sh` lines 478-487
- Windows launcher:
  - `scripts/windows/MarkdownViewerLauncher.c` lines 278-280

That behavior matters because "ship a sane default" is not the same as "force
this value forever." Users should still be able to override the theme through
their environment or persisted defaults.

## Why this belongs upstream
This is not only about `GSTheme`. GNUstep apps often need launch-time values
that fall into one of these categories:

- always override
- set only when unset
- seed a user-scoped default once, then respect later user changes

The current launch contract can only express the first category.

## Requested capability
Extend the launch environment model so each entry can declare its assignment
policy, for example:

- `override`
  Always set the environment variable.
- `ifUnset`
  Set it only when the variable is not already defined.

Longer-term, a user-default-seeding mode may also be useful for GNUstep
defaults, but `ifUnset` would already cover the main theme-default case.

## Example use case
The downstream manifest should be able to express logic equivalent to:

- Linux AppImage: default `GSTheme=Adwaita` only if `GSTheme` is unset
- Windows MSI: default `GSTheme=WinUXTheme` only if `GSTheme` is unset

without requiring app-specific launchers or wrapper scripts.

## Acceptance criteria
- The launch contract can distinguish unconditional and conditional environment
  assignments.
- The AppImage backend renders the conditional policy correctly in generated
  `AppRun`.
- The MSI backend renders the conditional policy correctly in the generated
  launcher.
- The docs include a GNUstep theme-default example showing how to ship a theme
  preference without preventing user override.

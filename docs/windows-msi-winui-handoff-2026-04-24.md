# Windows MSI / WinUITheme Handoff - 2026-04-24

## Current State

We validated the current Windows MSI work on OracleTestVMs/libvirt using a clean
Windows Server 2022 guest.

The installed `rc29` MSI contains `WinUITheme.theme` and the expected resource
payload under:

```text
C:\Users\Administrator\AppData\Local\ObjcMarkdown\runtime\lib\GNUstep\Themes\WinUITheme.theme
```

The theme bundle includes `WinUITheme.dll`, `Resources\Info-gnustep.plist`,
`Resources\ThemeImages`, and `Resources\ThemeTiles`. The artifact therefore does
not appear to be missing theme assets.

## Observed Problems

1. First visible launch from the `rc29` MSI came up with the stock GNUstep theme
   instead of `WinUITheme`.
2. Forcing `WinUITheme` caused malformed toolbar/menu/preferences rendering.
   Ordinary controls were drawn as radio/switch-like indicators.

## Layer Diagnosis

The malformed WinUI rendering is a `WinUITheme` bug, not a
`gnustep-packager` bug.

Evidence:

- The installed theme resources are present in the MSI payload.
- The same malformed rendering reproduced through the MSI launcher, the
  portable launcher, and direct app executable launch with `-GSTheme
  WinUITheme`.
- The direct executable launch bypasses `gnustep-packager` launcher behavior, so
  the broken drawing happens after GNUstep loads the theme.
- The local WinUITheme repo contains a known-good ObjcMarkdown screenshot
  baseline, which confirms ordinary buttons/segmented controls should not render
  as switch/radio controls.

Root cause found locally in:

- `~/git/gnustep/plugins-themes-winuitheme/Source/Rendering/WinUIThemeDrawing.m`
- `~/git/gnustep/plugins-themes-winuitheme/Source/Rendering/WinUIThemeControls.m`

The checkbox/radio classifiers call `rangeOfString:` on possibly nil image
names and compare the returned `.location` to `NSNotFound`. Sending
`rangeOfString:` to nil returns a zeroed `NSRange`, so `.location == 0`, which
is incorrectly treated as a match. As a result, image-less/text-only
`NSButtonCell`s can be classified as switch/radio controls.

## Local Fixes In Progress

WinUITheme local checkout has a local commit with nil guards around the
switch/radio image-name matching paths:

```text
ab1ac8f Fix image-less button classification
```

This commit still needs Windows/MSYS2 GNUstep validation and then needs to be
pushed before ObjcMarkdown can repin its MSI `themeInputs` entry away from the
currently packaged `914ee2d`.

ObjcMarkdown also has a local fallback fix in `ObjcMarkdownViewer/main.m`:

- `OMDWindowsBundledDefaultsToolPath()` now probes both `runtime` and `clang64`.
- `OMDWindowsPreferredThemeName()` now probes both
  `installRoot\runtime\lib\GNUstep\Themes` and
  `installRoot\clang64\lib\GNUstep\Themes`.

That ObjcMarkdown fallback fix is intentionally defensive. The packaged
first-launch default still belongs to `gnustep-packager`, but ObjcMarkdown
should correctly find the theme in the MSI runtime layout if fallback seeding is
needed.

## Validation Completed

ObjcMarkdown:

```sh
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
gmake
```

Result: passed.

ObjcMarkdown tests:

```sh
mkdir -p ~/GNUstep/Defaults/.lck
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
LD_LIBRARY_PATH=$PWD/ObjcMarkdown/obj:/usr/GNUstep/System/Library/Libraries \
  xctest ObjcMarkdownTests/ObjcMarkdownTests.bundle
```

Result: failed due local GNUstep/X/GDNC/defaults-lock environment issues already
seen in this workspace. Failures included inability to connect to X Server,
GDNC/pasteboard communication failures, and non-writable defaults lock
directory messages.

WinUITheme:

```sh
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
gmake
```

Result: the modified source files compile. Final link fails on this Linux host
because the theme makefile links Windows `gdi32`, which is unavailable here.
Windows visual validation still needs a Windows GNUstep/MSYS2 build.

## Best Path To A Working MSI

1. Build and validate WinUITheme commit `ab1ac8f` on a Windows/MSYS2 GNUstep
   host.
2. Capture ObjcMarkdown under `-GSTheme WinUITheme` and compare against the
   known-good screenshot in the WinUITheme repo.
3. Push the WinUITheme fix.
4. Update `packaging/manifests/windows-msi.manifest.json` to pin the new
   WinUITheme commit instead of `914ee2d`.
5. Keep the ObjcMarkdown `runtime` theme-probe fallback fix.
6. Build a fresh MSI using the current `gnustep-packager` pin, not the stale
   `rc29` artifact.
7. Validate on a clean OracleTestVMs/libvirt Windows VM:
   - first launch uses `WinUITheme`
   - Preferences and toolbar/menu rendering match the known-good baseline
   - `runtime\lib\GNUstep\Themes\WinUITheme.theme` is present
   - GNUstep defaults contain `GSTheme = WinUITheme`

## Important Next-Week Notes

- Do not use the existing `rc29` MSI as proof for the new packager default
  seeding path. It predates the current `gnustep-packager` theme/default
  changes.
- If a fresh MSI built with current `gnustep-packager` still does not first
  launch with `WinUITheme`, file that as a `gnustep-packager` launcher/defaults
  bug.
- If the fresh MSI contains the fixed WinUITheme commit and still renders
  malformed controls when launched directly with `-GSTheme WinUITheme`, continue
  investigation in WinUITheme or GNUstep runtime/theme behavior, not
  `gnustep-packager`.
- GitHub authenticated operations were blocked earlier because `gh auth status`
  did not show a valid active `danjboyd` session. Re-auth or switch accounts
  before dispatching hosted builds, pushing fixes, or creating releases.

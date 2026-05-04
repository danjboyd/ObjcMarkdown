# Windows MSI / WinUI Theme Handoff - 2026-05-04

## Completed

- Built `ObjcMarkdown-0.1.1-rc30-win64.msi` through the normal source-built Windows packaging path.
- Copied local artifacts to `dist/windows-msi-work/rc30/`:
  - `ObjcMarkdown-0.1.1-rc30-win64.msi`
  - `ObjcMarkdown-0.1.1-rc30-win64-portable.zip`
  - package metadata, diagnostics, update feed, and WiX PDB
- Confirmed the packaged metadata sets `GSTheme=WinUITheme` with `policy: ifUnset`.
- Confirmed the portable payload contains `runtime\lib\GNUstep\Themes\WinUITheme.theme\WinUITheme.dll` and the WinUI image resources.
- Ran clean Windows OracleTestVMs validation on libvirt test lease `lease-20260504204357-urui9v`; unattended install, runtime checks, launch smoke, TinyTeX smoke, and uninstall passed.
- Verified a live packaged app process loaded `WinUITheme.dll` from the installed runtime and app defaults reported `org.objcmarkdown.MarkdownViewer GSTheme WinUITheme`.
- Created an OCI fallback VM for manual testing after libvirt capacity/machine-type failure:
  - lease `lease-20260504205827-goi0wx`
  - RDP `141.148.172.165:3389`
  - user `opc`
  - staged files under `C:\Users\Public\Desktop\ObjcMarkdownManualTest`

## Repo Changes Made

- `ObjcMarkdownViewer/GNUmakefile`
  - Added `-lgdi32` for the MinGW viewer link.
- `packaging/scripts/stage-windows-runtime.sh`
  - Accepts Windows-style theme repo paths inside MSYS shells.
  - Merges `WinUITheme` and `Win11Theme` resources into staged runtime theme bundles.
  - Copies `ThemeImages` into both `Resources` and `Resources\GSThemeImages`.
  - Seeds CLANG64 runtime DLLs broadly enough to satisfy packaged runtime closure.
- `OpenIssues.md` / `ClosedIssues.md`
  - Closed the Windows MSI rebuild handoff issue with rc30 validation evidence.

## WinUI Dropdown Status

The MSI is shipping the latest upstream `plugins-themes-winuitheme` commit currently known:

`48d21f0a2ae97ca70a03197d93a305144635517f` - `Refine WinUI theme menu and control rendering`

The manual Windows screenshot shows Preferences popup controls are present but their selected titles and closed-dropdown chrome do not render correctly. That is not because the MSI has an older WinUI theme.

Current read:

- ObjcMarkdown now uses native `NSPopUpButton` instances for Preferences controls; the old custom Preferences popup overlay path is disabled.
- The latest WinUI theme has substantial popup/menu support, but the closed `NSPopUpButtonCell` path still appears incomplete on Windows.
- The likely next fix belongs in `plugins-themes-winuitheme`, not ObjcMarkdown:
  - make the `NSPopUpButtonCell` override draw the full closed control surface itself
  - draw background, selected title, divider/lane, and chevron in one coherent path
  - avoid depending on GNUstep's split default interior/title/image drawing for the closed popup button

Relevant WinUI theme files:

- `Source/Rendering/WinUIThemeControls.m`
  - `drawButton:in:view:style:state:`
  - `_overrideNSPopUpButtonCellMethod_drawInteriorWithFrame:inView:`
  - `_overrideNSPopUpButtonCellMethod_drawTitleWithFrame:inView:`
  - `_overrideNSPopUpButtonCellMethod_drawImageWithFrame:inView:`
- `Source/Rendering/WinUIThemeMenusAndData.m`
  - popup-owned `NSMenuView` detection and popup menu row rendering

## Validation Notes

- Local `gmake` completed successfully.
- Sandboxed XCTest failed due environment limitations: no usable X server, unwritable GNUstep defaults lock path, and GDNC/pasteboard startup failures.
- Escalated XCTest progressed further with X access but exited abnormally before a clean summary; this remains an environment/tooling validation gap, not a known MSI blocker.
- GitHub CLI auth is invalid for both configured accounts in this environment; pushing depends on regular Git credentials rather than `gh`.

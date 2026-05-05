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

The MSI was intended to ship the latest upstream `plugins-themes-winuitheme`
commit currently known:

`48d21f0a2ae97ca70a03197d93a305144635517f` - `Refine WinUI theme menu and control rendering`

Follow-up manual testing showed that a hand-built ObjcMarkdown plus hand-built
WinUI theme renders Preferences dropdowns correctly on Windows, while the rc30
MSI does not. That means the rc30 package likely bundled a stale compiled
`WinUITheme.dll` while merging current theme resources.

Current read:

- ObjcMarkdown now uses native `NSPopUpButton` instances for Preferences controls; the old custom Preferences popup overlay path is disabled.
- The latest compiled WinUI theme appears to fix the Preferences dropdown rendering.
- The rc30 MSI validation proved `WinUITheme.dll` existed and was loaded, but
  did not prove that the DLL was rebuilt from the pinned WinUI source commit.
- The likely next fix belongs in the MSI packaging flow:
  - run the full `gnustep-packager` pipeline without `GP_SKIP_THEME_PROVISION=1`
  - make `provision -Backend msi` rebuild and stage the complete
    `WinUITheme.theme`, including `WinUITheme.dll`
  - require `metadata\gnustep-packager-theme-report.json` as provenance for the
    staged theme binary

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

## Fresh-Binary Rebuild Process

For the next MSI, rebuild from a clean Windows build environment with the full
`gnustep-packager` pipeline:

```powershell
.\gnustep-packager\scripts\run-packaging-pipeline.ps1 `
  -Manifest .\packaging\manifests\windows-msi.manifest.json `
  -Backend msi `
  -PackageVersion 0.1.1-rc31 `
  -InstallHostDependencies `
  -RunSmoke
```

Before running it, remove stale generated outputs:

```powershell
Remove-Item -Recurse -Force .\dist\packaging\windows\stage,
  .\dist\packaging\windows\tmp,
  .\dist\packaging\windows\packages,
  .\dist\packaging\windows\logs -ErrorAction SilentlyContinue
```

Do not skip theme provisioning. The rebuild is fresh only if:

- the app build, stage, provision, package, and validation logs are all from
  the same run
- the staged payload contains `metadata\gnustep-packager-theme-report.json`
- that report records `WinUITheme` at
  `48d21f0a2ae97ca70a03197d93a305144635517f`
- the report's staged theme bundle contains `WinUITheme.dll`
- the installed app loads
  `runtime\lib\GNUstep\Themes\WinUITheme.theme\WinUITheme.dll`
- a clean Windows VM shows the Preferences dropdown controls rendered correctly

If the theme report is missing or reused from an older run, the MSI should not
be treated as a fresh-binary rebuild.

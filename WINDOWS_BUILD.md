# Windows Build Bootstrap

## Status

This repository is validated on GNUstep/Linux first. Windows support is an active bring-up target.
We use WSL for Codex ergonomics, but all Windows builds should use MSYS2 `clang64` from WSL.

This document gives two paths:
- Fast path: WSL2 (recommended for immediate productivity)
- Native Windows GNUstep path (experimental)

## Path A (Recommended): WSL2 GNUstep

Use this when you need a working Windows-hosted environment quickly.

1. Install WSL2 and an Ubuntu distro.
2. In WSL, install GNUstep, `gmake`, compiler toolchain, `pkg-config`, and `cmark` dev headers/libs.
3. Clone the repo in WSL.
4. Build and run:

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
gmake
gmake run TableRenderDemo.md
```

5. Run tests:

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
mkdir -p ~/GNUstep/Defaults/.lck
LD_LIBRARY_PATH=$PWD/ObjcMarkdown/obj:/usr/GNUstep/System/Library/Libraries xctest ObjcMarkdownTests/ObjcMarkdownTests.bundle
```

## Path B: Native Windows GNUstep (Experimental)

### 1) Required Components

- GNUstep make/base/gui toolchain for Windows
- Objective-C capable compiler toolchain
- `gmake`
- `pkg-config`
- `cmark` headers and library (`cmark.h`, linkable `cmark`)
- `xctest` (from GNUstep tools-xctest) if you want unit tests on Windows

### 2) Environment Expectations

You need a shell session where GNUstep variables are set (equivalent to sourcing `GNUstep.sh` on Linux).

Sanity checks:

```bash
gmake --version
pkg-config --cflags cmark
pkg-config --libs cmark
```

If these fail, do not continue until fixed.

### 3) Build

From repo root:

```bash
gmake
```

This builds:
- `third_party/libs-OpenSave/Source`
- `third_party/TextViewVimKitBuild`
- `ObjcMarkdown`
- `MarkdownViewer`
- `ObjcMarkdownTests`

### 4) Run

Preferred:

```bash
gmake run TableRenderDemo.md
```

If `openapp` is unavailable in your Windows GNUstep environment, run the app binary directly:

```bash
ObjcMarkdownViewer/MarkdownViewer.app/MarkdownViewer TableRenderDemo.md
```

Theme note (Windows):
- The MSYS2 helper script defaults to `WinUXTheme` because `Sombre` is unstable on Windows.
- To try Sombre anyway, run with `OMD_USE_SOMBRE_THEME=1` (expect possible launch failures).

### 5) Tests

```bash
mkdir -p ~/GNUstep/Defaults/.lck
xctest ObjcMarkdownTests/ObjcMarkdownTests.bundle
```

If dynamic library loading fails on Windows, add repo build output directories to your runtime DLL search path (`PATH`) before running tests/app.

Suggested directories:
- `ObjcMarkdown/obj`
- `third_party/libs-OpenSave/Source/obj`
- `third_party/TextViewVimKitBuild/obj`

## Repo-Specific Windows Blockers to Expect

1. `cmark` not found
- Symptom: `cmark.h` missing or `-lcmark` link errors.
- Fix: install/provide cmark dev package and ensure `pkg-config` can resolve it.

2. `dispatch` / `-ldispatch` link errors
- Symptom: unresolved `dispatch_*` symbols.
- Fix: install/provide libdispatch for your Windows GNUstep toolchain, or patch linkage for a no-dispatch fallback build.

3. `openapp` missing
- Symptom: `gmake run` fails.
- Fix: launch the app binary directly.

4. Test lock directory missing
- Symptom: defaults/lock file errors while running tests.
- Fix: create `~/GNUstep/Defaults/.lck`.

5. Sombre theme crash (Windows)
- Symptom: launch under `GSTheme=Sombre` fails with an `NSInvalidArgumentException` and no usable main window.
- Fix: use `WinUXTheme` (default in `scripts/omd-viewer-msys2.sh`) unless you are actively investigating Sombre.
- If you want Sombre enabled: rebuild and install Sombre with the same MSYS2 toolchain version as the app so `Sombre.dll` links to the same `gnustep-base-*.dll`.

## First-Pass Bring-Up Checklist

- `gmake` completes without errors
- App launches and renders `TableRenderDemo.md`
- `xctest ObjcMarkdownTests/ObjcMarkdownTests.bundle` executes
- Toolbar icons are legible in current theme
- Split view, explorer, and table rendering are usable

## Next Windows Follow-Ups

- Add a Windows-specific install script (or package manager recipe list)
- Add a Windows CI lane once toolchain is stable
- Add Windows file association/installer tasks (see `FileAssociations.md`)

## Packaging (MSI + Portable ZIP)

This repo includes a staging script that gathers the app bundle, GNUstep resources,
and runtime DLL dependencies into a single directory.

```bash
./scripts/windows/stage-runtime.sh dist/ObjcMarkdown
```

The CI workflow then:
- Harvests `dist/ObjcMarkdown` into an MSI using WiX.
- Builds a portable ZIP from the same staging directory.

Runtime layout:
- GNUstep runtime files are installed under `C:\clang64` (mirroring MSYS2 layout).
- The app launcher adds `C:\clang64\bin` to `PATH` before launching.
- The portable ZIP includes `PortableSetup.cmd` to copy the runtime into `C:\clang64`.

## Windows Builds From WSL (MSYS2 clang64)

We are typically inside WSL, but Windows builds must be performed by MSYS2 `clang64`.
Initiate the Windows build from WSL by invoking the MSYS2 bash on Windows.

Example (adjust MSYS2 path if different):

```bash
/mnt/c/msys64/clang64.exe -lc "cd /c/Users/Support/git/ObjcMarkdown && ./scripts/windows/build-msys2.sh"
```

Notes:
- Use the Windows repo path, not the WSL path, in the `cd` inside MSYS2.
- If you need to pass environment variables, set them inside the `-lc` command.

## Clean VM MSI Validation (Windows Sandbox)

Use Windows Sandbox to validate the MSI on a clean Windows environment (no MSYS2/GNUstep preinstalled).
This should be done after a successful MSYS2 `clang64` build and packaging run.

1) Confirm Sandbox feature is enabled (PowerShell, admin):

```powershell
Get-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM | Select-Object State
```

Expected: `Enabled`.

2) Create a Sandbox config file in the repo, e.g. `ObjcMarkdownSandbox.wsb`:

```xml
<Configuration>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>C:\Users\Support\git\ObjcMarkdown\dist</HostFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>cmd /c "dir C:\Users\WDAGUtilityAccount\Desktop\dist && start C:\Users\WDAGUtilityAccount\Desktop\dist"</Command>
  </LogonCommand>
</Configuration>
```

3) Launch the `.wsb` by double-clicking it in Windows.

4) In Sandbox:
- Open the mapped `dist` folder.
- Run the MSI (for example: `ObjcMarkdown-0.0.0.0-win64.msi`).
- Confirm install succeeds, Start Menu shortcut exists, and uninstall entry exists.
- Launch the app via Start Menu shortcut (or `C:\Program Files (x86)\ObjcMarkdown\MarkdownViewer.cmd`) and verify no missing DLL/runtime errors.

Important:
- Do not use `MarkdownViewer.exe` directly for validation. The MSI ships `MarkdownViewer.cmd` to set runtime `PATH` first; direct `.exe` launch can fail with missing DLL errors by design.

5) Record findings in `OpenIssues.md` issue 7:
- Missing DLLs or runtime errors.
- Exact MSI filename tested and observed behavior.

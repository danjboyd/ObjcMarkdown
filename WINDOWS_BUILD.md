# Windows Build Bootstrap

## Status

This repository is validated on GNUstep/Linux first. On Windows, the only supported
build method is MSYS2 `clang64`, followed by staging and MSI packaging.

WSL may be used as a convenience shell to invoke the Windows MSYS2 environment, but
WSL GNUstep and native Windows GNUstep bring-up are not supported build paths for
this project.

## Supported Windows Build Method: MSYS2 `clang64`

### 1) Required Components

- MSYS2 with the `clang64` environment
- GNUstep make/base/gui toolchain installed in MSYS2 `clang64`
- Objective-C capable compiler toolchain
- `make`
- `pkg-config`
- `cmark` headers and library (`cmark.h`, linkable `cmark`; MSYS2 exposes this via `libcmark.pc`)
- `xctest` (from GNUstep tools-xctest) if you want unit tests on Windows
- WiX if you are producing the MSI package

### 2) Environment Expectations

Run all Windows builds inside the MSYS2 `clang64` environment. If you launch the
build from WSL, invoke MSYS2 on the Windows side and use the Windows repo path.

Before building, load the MSYS2 profile and GNUstep environment:

```bash
source /etc/profile
source /clang64/share/GNUstep/Makefiles/GNUstep.sh
```

Sanity checks:

```bash
make --version
pkg-config --cflags libcmark
pkg-config --libs libcmark
```

If these fail, do not continue until fixed.

### 2a) PowerShell / Codex Entry Point

When you are driving the build from Windows PowerShell, do not try to build in plain
PowerShell directly. Use PowerShell only as the launcher for the supported MSYS2
`clang64` shell.

This repo includes a helper script for that workflow:

```powershell
.\scripts\windows\build-from-powershell.ps1
```

That default command performs the equivalent of:

```powershell
& 'C:\msys64\usr\bin\env.exe' 'MSYSTEM=CLANG64' 'CHERE_INVOKING=1' '/usr/bin/bash' '-lc' 'source /etc/profile; source /clang64/share/GNUstep/Makefiles/GNUstep.sh; cd /c/Users/Support/git/ObjcMarkdown; make'
```

Important:
- Keep the `cd /c/.../ObjcMarkdown` inside the MSYS2 command. Do not assume the
  PowerShell working directory will carry over correctly into MSYS2.
- The helper script resolves the repo root automatically from its own location, so it
  is suitable for Codex sessions launched from PowerShell in this repo.
- Override `-MsysRoot` if MSYS2 is installed somewhere other than `C:\msys64`.

### 3) Build

From the repo root inside MSYS2 `clang64`:

```bash
source /etc/profile
source /clang64/share/GNUstep/Makefiles/GNUstep.sh
make
```

From PowerShell/Codex, use:

```powershell
.\scripts\windows\build-from-powershell.ps1 -Task build
```

This builds:
- `third_party/libs-OpenSave/Source`
- `third_party/TextViewVimKitBuild`
- `ObjcMarkdown`
- `MarkdownViewer`
- `ObjcMarkdownTests`

Windows/MSYS2 note:
- The current tree includes a viewer-target workaround for the MSYS2 `clang64` + GNUstep header issue where `dispatch/io.h` fails with `unknown type name 'mode_t'`.
- The workaround is applied in `ObjcMarkdownViewer/GNUmakefile` by forcing `sys/types.h` into the Objective-C compile and defining `mode_t` for that target's Windows build.
- If that error reappears in a future Codex session, inspect the actual compile line with `make -n messages=yes` inside `ObjcMarkdownViewer/` before changing unrelated code.

### 4) Run

```bash
source /etc/profile
source /clang64/share/GNUstep/Makefiles/GNUstep.sh
make run TableRenderDemo.md
```

From PowerShell/Codex, use:

```powershell
.\scripts\windows\build-from-powershell.ps1 -Task run -RunTarget TableRenderDemo.md
```

If `openapp` is unavailable in your MSYS2 `clang64` environment, run the app binary directly:

```bash
ObjcMarkdownViewer/MarkdownViewer.app/MarkdownViewer.exe TableRenderDemo.md
```

Theme note (Windows):
- The MSYS2 helper script defaults to `WinUXTheme` because `Sombre` is unstable on Windows.
- To try Sombre anyway, run with `OMD_USE_SOMBRE_THEME=1` (expect possible launch failures).

### 5) Tests

```bash
source /etc/profile
source /clang64/share/GNUstep/Makefiles/GNUstep.sh
mkdir -p ~/GNUstep/Defaults/.lck
xctest ObjcMarkdownTests/ObjcMarkdownTests.bundle
```

From PowerShell/Codex, use:

```powershell
.\scripts\windows\build-from-powershell.ps1 -Task test
```

The PowerShell helper creates `~/GNUstep/Defaults/.lck` and prepends the repo build
output directories to `PATH` before invoking `xctest`.

If dynamic library loading fails on Windows, add repo build output directories to your runtime DLL search path (`PATH`) before running tests/app.

Suggested directories:
- `ObjcMarkdown/obj`
- `third_party/libs-OpenSave/Source/obj`
- `third_party/TextViewVimKitBuild/obj`

## Repo-Specific Windows Blockers to Expect

1. `cmark` not found
- Symptom: `cmark.h` missing or `-lcmark` link errors.
- Fix: install/provide cmark dev package and ensure `pkg-config --libs libcmark` works.

2. GNUstep environment not loaded
- Symptom: errors such as `/common.make: No such file or directory`.
- Fix: source `/etc/profile` and `/clang64/share/GNUstep/Makefiles/GNUstep.sh` before running `make`.

3. `dispatch` / `-ldispatch` link errors
- Symptom: unresolved `dispatch_*` symbols.
- Fix: install/provide libdispatch for your Windows GNUstep toolchain, or patch linkage for a no-dispatch fallback build.

4. MSYS2 `mode_t` header break
- Symptom: Windows app sources fail while including AppKit/Foundation/dispatch with an error like `dispatch/io.h: unknown type name 'mode_t'`.
- Fix: keep the Windows-specific viewer build workaround in `ObjcMarkdownViewer/GNUmakefile` that forces `sys/types.h` and defines `mode_t` for the Objective-C compile.
- Diagnostic: run `make -n messages=yes` in `ObjcMarkdownViewer/` and verify the compile line still includes the Windows workaround flags.

5. `openapp` missing
- Symptom: `make run` fails.
- Fix: launch the app binary directly.

6. Test lock directory missing
- Symptom: defaults/lock file errors while running tests.
- Fix: create `~/GNUstep/Defaults/.lck`.

7. Sombre theme crash (Windows)
- Symptom: launch under `GSTheme=Sombre` fails with an `NSInvalidArgumentException` and no usable main window.
- Fix: use `WinUXTheme` (default in `scripts/omd-viewer-msys2.sh`) unless you are actively investigating Sombre.
- If you want Sombre enabled: rebuild and install Sombre with the same MSYS2 toolchain version as the app so `Sombre.dll` links to the same `gnustep-base-*.dll`.

## First-Pass Bring-Up Checklist

- `make` completes without errors
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
and runtime DLL dependencies into a single directory. Windows release artifacts are
expected to come from this MSYS2 `clang64` build output.

Run staging from MSYS2 `clang64`, not plain WSL/Linux. The staging script builds the
production `MarkdownViewer.exe` GUI launcher only when it is running in a Windows/MSYS2
environment.

```bash
./scripts/windows/stage-runtime.sh dist/ObjcMarkdown
```

From PowerShell/Codex, use:

```powershell
.\scripts\windows\build-from-powershell.ps1 -Task stage -StageDir dist/ObjcMarkdown
```

The CI workflow then:
- Harvests `dist/ObjcMarkdown` into an MSI using WiX.
- Builds a portable ZIP from the same staging directory.

Runtime layout:
- GNUstep runtime files are installed under `C:\clang64` (mirroring MSYS2 layout).
- The production launcher is a GUI-mode `MarkdownViewer.exe` that configures the runtime path and starts the bundled app without opening a console window.
- The launcher prefers a bundled `clang64` folder when present, and otherwise falls back to `C:\clang64\bin`.
- The portable ZIP includes `PortableSetup.cmd` to copy the runtime into `C:\clang64`.

For the OCI-based clean-machine MSI validation workflow, including the current
golden Windows image and the intended `scp`/`ssh` validation loop, see
[docs/windows-oci-msi-validation.md](docs/windows-oci-msi-validation.md).

## Windows Builds From WSL (MSYS2 clang64)

We are typically inside WSL, but Windows builds must be performed by MSYS2 `clang64`.
Initiate the Windows build from WSL by invoking the MSYS2 environment on Windows,
then source the MSYS2 profile and GNUstep shell setup before calling `make`.

Example (adjust paths if different):

```bash
powershell.exe -NoProfile -Command "& 'C:\msys64\usr\bin\env.exe' 'MSYSTEM=CLANG64' 'CHERE_INVOKING=1' '/usr/bin/bash' '-lc' 'source /etc/profile; source /clang64/share/GNUstep/Makefiles/GNUstep.sh; cd /c/Users/Support/git/ObjcMarkdown; make'"
```

Notes:
- Use the Windows repo path, not the WSL path, in the `cd` inside MSYS2.
- The repo no longer uses `scripts/windows/build-msys2.sh`; invoke `make` directly after loading the environment.
- This WSL-to-Windows PowerShell/MSYS2 path was used successfully to build the current app from this repo.

## PowerShell Helper Summary

The repo helper script wraps the supported MSYS2 `clang64` path for common Windows
tasks:

```powershell
.\scripts\windows\build-from-powershell.ps1
.\scripts\windows\build-from-powershell.ps1 -Task test
.\scripts\windows\build-from-powershell.ps1 -Task run -RunTarget TableRenderDemo.md
.\scripts\windows\build-from-powershell.ps1 -Task stage -StageDir dist/ObjcMarkdown
.\scripts\windows\build-from-powershell.ps1 -Task command -Command 'make -n messages=yes'
```

Use `-Task command` when you need an arbitrary MSYS2/GNUstep command without manually
rewriting the `env.exe ... bash -lc ...` wrapper in PowerShell.

## Clean VM MSI Validation (OCI)

The canonical clean-machine validation path is the OCI golden-image workflow in
`docs/windows-oci-msi-validation.md`, not Windows Sandbox.

For a one-shot run from PowerShell:

```powershell
.\scripts\windows\oci-run-msi-validation.ps1 `
  -Version 0.1.0 `
  -IdentityFile C:\Users\Support\.ssh\id_rsa `
  -TemporarilyRestrictSshIngress `
  -RunSmoke
```

If you are reaching the guest through the office jump host:

```powershell
.\scripts\windows\oci-run-msi-validation.ps1 `
  -Version 0.1.0 `
  -IdentityFile C:\Users\Support\.ssh\id_rsa `
  -JumpHost iep-vm2 `
  -TemporarilyRestrictSshIngress `
  -RunSmoke
```

To validate the exact tagged CI artifact produced by GitHub Actions instead of a local build:

```powershell
gh run download 23612901170 -n objcmarkdown-windows-0.1.1 -D dist\ci-artifacts\23612901170

.\scripts\windows\oci-run-msi-validation.ps1 `
  -MsiPath dist\ci-artifacts\23612901170\ObjcMarkdown-0.1.1.0-win64.msi `
  -IdentityFile C:\Users\Support\.ssh\id_rsa `
  -TemporarilyRestrictSshIngress `
  -RunSmoke `
  -LogDir dist\oci-logs\ci-23612901170
```

Lower-level OCI entry points:

- `.\scripts\windows\oci-launch-validation-vm.ps1`
- `.\scripts\windows\oci-open-rdp-rule.ps1`
- `.\scripts\windows\oci-push-and-test-msi.ps1`
- `.\scripts\windows\oci-terminate-validation-vm.ps1`

Notes:

- The automation launches a fresh VM from the OCI golden image, copies the MSI with `scp`, runs `scripts/windows/validate-msi.ps1` over `ssh`, collects logs under `dist/oci-logs`, and terminates the VM unless you pass `-KeepVm`.
- Use `-OpenRdp` only when manual visual inspection is needed after the automated validation pass. The RDP rule helper narrows access to the current public IP by default.
- Use `-TemporarilyRestrictSshIngress` when the subnet still exposes SSH on `0.0.0.0/0`. That switch adds a temporary narrow port `22` rule for the current public IP, removes the broad rule during validation, then restores the original rule after teardown unless you keep the VM.
- Do not use `app\MarkdownViewer.app\MarkdownViewer.exe` directly for validation. The MSI ships a top-level `MarkdownViewer.exe` launcher that sets runtime state first; launching the inner app binary directly can still fail with missing DLL errors by design.

Windows Sandbox can still be used as an informal local smoke check, but it is no
longer the tracked release-validation path for this repo.

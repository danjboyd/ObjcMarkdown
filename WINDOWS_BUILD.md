# Windows Build Bootstrap

## Status

This repository is validated on GNUstep/Linux first. Windows support is an active bring-up target.

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

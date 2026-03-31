# Feature Request: AppImage backend should support strict runtime-closure validation for packaged ELF payloads

## Summary
The current AppImage backend validates packaging structure, desktop metadata,
and smoke launch behavior, but it does not verify that the packaged ELF payload
is actually self-contained.

## Status
Addressed in the current `gnustep-packager` working tree on `2026-03-31`.

For real GNUstep desktop apps, "the AppImage launched on the build host" is not
strong enough. We need a backend validation mode that checks runtime closure and
rejects AppImages that still depend on missing or out-of-bundle libraries.

## Evidence
- `backends/appimage/lib/appimage.ps1` currently validates:
  - required extracted paths
  - desktop entry rendering
  - optional `desktop-file-validate`
  - smoke launch
  - see lines 1509-1543
- `docs/appimage-runtime-policy.md` explicitly says the consumer must stage the
  full Linux runtime closure before packaging:
  - lines 36-39
- `backends/appimage/README.md` lists the current validation scope and names the
  staged-runtime-closure limitation explicitly:
  - validation scope at lines 49-55
  - known limitation at lines 64-67

## Downstream impact
`ObjcMarkdown` currently compensates with its own Linux validation script:

- `scripts/linux/validate-appimage.sh`
  - rejects packaged ELF files whose `RUNPATH` / `RPATH` escapes the AppDir:
    lines 70-94
  - runs `ldd` under packaged library paths and fails on unresolved
    dependencies:
    lines 96-104
  - applies those checks across bundled libraries, GNUstep backends, themes,
    and the app binary:
    lines 230-242

That validation exists because the product goal is "run on a Linux box without
preinstalled GNUstep libraries." The external tool should be able to enforce
that property directly.

## Requested capability
Add an AppImage validation mode that checks packaged ELF closure after
extraction, for example:

- scan packaged ELF files under the extracted AppDir
- reject absolute or host-escaping `RUNPATH` / `RPATH` entries
- resolve dependencies under the packaged environment and fail when non-system
  libraries are missing
- optionally allow a documented system-library allowlist

This can remain a validation feature even if dependency harvesting stays out of
scope.

## Why this belongs upstream
This is not `ObjcMarkdown`-specific logic. Any real GNUstep AppImage consumer
needs confidence that:

- the packaged app binary resolves correctly
- GNUstep backends and theme libraries resolve correctly
- the AppImage does not accidentally depend on host-installed GNUstep libraries

Without that, every downstream must reinvent its own ELF validation layer.

## Proposed shape
Possible manifest/backend settings:

- `backends.appimage.validation.runtimeClosure: strict|off`
- `backends.appimage.validation.allowedSystemLibraries[]`
- `backends.appimage.validation.allowedExternalRunpaths[]`

Exact naming is flexible; the key requirement is a first-class strict packaged
runtime check.

## Acceptance criteria
- The backend can fail validation when a packaged ELF has unresolved non-system
  dependencies under the packaged environment.
- The backend can fail validation when a packaged ELF contains host-escaping
  `RUNPATH` / `RPATH` entries.
- The validation logs identify which binary failed and why.
- The docs explain how strict AppImage runtime validation relates to the
  existing "consumer must stage closure" boundary.

# gnustep-packager Bug Report: Windows Bundle Dependency Closure Misses GNUstep Backend DLL Dependencies

## Summary

On Windows MSI packaging for `ObjcMarkdown`, the packaged GNUstep backend bundle
was present in the installed runtime, but the DLLs required to load it were not.
On a clean Windows VM, the installed app failed at startup because
`libgnustep-back-032.dll` could not load.

Observed missing runtime DLLs from the shipped artifact included:

- `libcairo-2.dll`
- `libfontconfig-1.dll`
- `libfreetype-6.dll`

## User-Visible Failure

The installed Start Menu shortcut launched the packager-generated launcher, but
the app exited immediately without opening a window.

Startup log from the clean Windows test VM:

```text
NSApplication.m:319  Assertion failed in BOOL initialize_gnustep_backend(void).
Can't load object file from backend at path
C:/Program Files (x86)/ObjcMarkdown/clang64/lib/GNUstep/Bundles/libgnustep-back-032.bundle
```

## Reproduction Context

- App: `ObjcMarkdown`
- Backend: Windows MSI
- Runtime layout: GNUstep app plus staged `clang64` runtime
- Validation environment: fresh OracleTestVMs Windows Server 2022 VM
- Installed artifact source: GitHub Actions Windows packaging artifact

The portable ZIP and installed MSI both contained:

- `clang64/lib/GNUstep/Bundles/libgnustep-back-032.bundle/libgnustep-back-032.dll`

But both were missing:

- `clang64/bin/libcairo-2.dll`
- `clang64/bin/libfontconfig-1.dll`
- `clang64/bin/libfreetype-6.dll`

## Root Cause Found Downstream

The downstream stage script had stale dependency-harvest logic that collected
dependencies from `libgnustep-back-031` instead of the actually staged
`libgnustep-back-032`.

That downstream bug is now fixed locally, but it exposed a packager gap: the
packaging pipeline did not fail even though a staged bundle could not load on a
clean machine due to missing dependent DLLs.

## Expected Behavior

For Windows packaging, bundle and plugin DLLs should participate in dependency
closure validation, not just the main launcher executable and a small set of
top-level runtime DLLs.

At minimum, if a staged bundle such as:

- `runtime/lib/GNUstep/Bundles/libgnustep-back-032.bundle/libgnustep-back-032.dll`

depends on additional DLLs that are not present in the packaged runtime, the
packaging validation step should fail before publishing the artifact.

## Requested Upstream Improvement

Add a Windows validation phase that:

1. Enumerates bundle/plugin DLLs under staged runtime roots such as:
   - `runtime/lib/GNUstep/Bundles`
   - `runtime/lib/GNUstep/Themes`
   - similar plugin/bundle directories defined by the payload layout
2. Computes their recursive DLL dependency closure.
3. Verifies every non-system dependency is present in the packaged runtime.
4. Emits a focused failure report listing:
   - the staged DLL that could not load
   - the missing dependent DLL names
   - the path locations searched during validation

## Why This Matters

Without this check, Windows artifacts can pass staged-layout validation and even
appear structurally complete while still failing instantly on a clean VM.

This is a high-value validation improvement because:

- the failure only becomes visible on a clean machine
- the launcher may still exit `0`, making the defect look like a shortcut or
  GUI issue
- GNUstep bundle loading depends on runtime DLL presence beyond the main app
  executable

## Suggested Acceptance Test

Create an integration test fixture where a staged bundle DLL intentionally
depends on a non-system DLL that is omitted from the runtime bin directory.

Expected packager result:

- packaging validation fails
- diagnostics identify the bundle DLL and the missing dependency

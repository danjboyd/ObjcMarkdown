# gnustep-packager Feature Request: Better Windows Diagnostics for Bundle-Present but Runtime-Incomplete Failures

## Summary

On Windows, a packaged app can fail on a clean VM even when:

- the app launcher exists
- the GNUstep backend bundle exists
- the package installs successfully

In the observed case, the actual issue was:

- the backend DLL was present
- required dependent DLLs were missing
- the launcher exited `0`
- no user-visible error appeared from the Start Menu launch

That makes the defect look like a shortcut problem or a GUI quirk when it is
really a runtime completeness problem.

## Requested Feature

When Windows packaging validation or smoke launch fails, emit diagnostics that
differentiate between:

1. launcher missing
2. launcher failed to start child process
3. target app process started and crashed
4. GNUstep bundle present but failed to load
5. bundle dependency closure incomplete

## Useful Diagnostic Output

The packager should ideally surface:

- the launcher path used
- the target app path used
- whether the child app process was observed
- bundle load failures captured from stdout/stderr or startup logs
- missing dependent DLLs for any bundle or plugin that could not load

Example of the kind of message that would have shortened diagnosis:

```text
Windows smoke failed: GNUstep backend bundle was present but could not load.
Bundle: runtime/lib/GNUstep/Bundles/libgnustep-back-032.bundle/libgnustep-back-032.dll
Missing dependencies: libcairo-2.dll, libfontconfig-1.dll, libfreetype-6.dll
```

## Why This Matters

The current failure mode is expensive to diagnose:

- install succeeds
- Start Menu entry exists
- launcher exits successfully
- only a clean machine reveals the defect

Richer diagnostics would shorten the loop for downstream packagers and make
Windows GUI packaging much less opaque.

## Suggested Acceptance Test

Create a Windows smoke fixture where:

- the main launcher exists
- the app bundle exists
- one required backend dependency is intentionally omitted

Expected result:

- smoke validation fails
- diagnostics identify the missing dependency and classify the failure as a
  bundle/runtime completeness issue rather than a generic launch failure

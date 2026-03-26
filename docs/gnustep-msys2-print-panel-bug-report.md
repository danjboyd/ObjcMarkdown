# GNUstep Bug Report Draft: Windows/MSYS2 `NSPrintOperation` fails loading print panel resource

## Project / Component

- Project: GNUstep
- Package: `gnustep-gui` (`libs-gui`)
- Area: AppKit printing / print panel on Windows
- Suspected classes: `NSPrintOperation`, `NSPrintPanel`, related print-panel resource loading

## Summary

On Windows under MSYS2 `clang64`, invoking `NSPrintOperation` from a GNUstep GUI app fails with:

`Could not load print panel resource`

The same app and code path work on GNUstep/Linux. This appears to be a Windows-specific GNUstep GUI printing/resource issue rather than an application rendering problem.

## Environment

- OS: Windows 11
- Shell/toolchain: MSYS2 `clang64`
- Compiler: clang from MSYS2 `clang64`
- GNUstep environment loaded from:
  - `source /etc/profile`
  - `source /clang64/share/GNUstep/Makefiles/GNUstep.sh`
- App type: GNUstep GUI application using AppKit text rendering and `NSPrintOperation`

## Observed Behavior

When the app attempts to print, or when it previously attempted PDF export via the print subsystem, GNUstep shows an error dialog:

`Could not load print panel resource`

Behavior seen in the app:

- Linux build: print flow works
- Windows/MSYS2 build: print flow fails with the print-panel-resource error
- The failure occurs even though the app can otherwise render the document normally in its window

## Expected Behavior

`NSPrintOperation` should either:

- show a working print panel on Windows, or
- successfully run without requiring a missing print-panel resource when configured not to show the panel

At minimum, `runOperation` should not fail because a print-panel resource cannot be loaded.

## Minimal Repro Shape

The failure happens from a standard AppKit print path:

```objc
NSPrintOperation *operation = [NSPrintOperation printOperationWithView:printView
                                                             printInfo:printInfo];
[operation setShowsPrintPanel:YES];
[operation setShowsProgressPanel:YES];
BOOL ok = [operation runOperation];
```

On Windows/MSYS2 `clang64`, this triggers the print-panel-resource failure.

We also tested:

```objc
[operation setShowsPrintPanel:NO];
```

but the Windows print path still did not behave correctly, which suggests the problem may be deeper than just the visible panel presentation.

## Why this looks like a GNUstep issue

- The exact same application-level feature works on GNUstep/Linux.
- The Windows failure references loading the print panel resource, which points at GNUstep GUI/AppKit infrastructure rather than app-specific document code.
- We were able to work around PDF export only by bypassing GNUstep printing entirely on Windows.

## Application Context

The reproducing app is an Objective-C GNUstep Markdown viewer that prepares a printable `NSTextView`/AppKit view and then uses `NSPrintOperation`.

The prepared print view is valid:

- it renders correctly in-app
- it has normal `NSPrintInfo`
- non-print export paths work

The failure is specifically at print execution time on Windows/MSYS2.

## Actual User-Facing Error

The dialog text shown by GNUstep is:

`Could not load print panel resource`

## Notes

- This report is about Windows/MSYS2 `clang64`.
- The app also observed that Windows PDF export through GNUstep printing either failed or produced incorrect output, while a browser-based fallback produced a valid PDF. That reinforces the suspicion that the GNUstep Windows print stack is the unstable piece.
- If maintainers want it, we can provide a small standalone repro app that creates a text view and calls `NSPrintOperation`.

## Suggested Title

`gnustep-gui on Windows/MSYS2 clang64: NSPrintOperation fails with "Could not load print panel resource"`

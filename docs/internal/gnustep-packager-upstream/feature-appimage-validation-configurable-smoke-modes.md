# Feature Request: AppImage smoke validation should support generic GUI-app launch modes

## Summary

The current AppImage smoke-validation contract is effectively "pass a marker
path as argv[1] and require the packaged app to create that file." That
matches the sample fixture, but it is too specific for real GUI apps.

## Type

Feature request

## Priority

Medium to high. Structural validation is already useful, but realistic smoke
validation for downstream GUI apps needs a more general contract.

## Observed In

- `gnustep-packager` commit: `d1edc0075311934d85e99c59783c74e62ce38bc8`
- downstream test case: `ObjcMarkdown`

## Affected Files

- `backends/appimage/lib/appimage.ps1`
- `examples/sample-linux/package.manifest.json`
- `examples/sample-linux/src/SampleGNUstepLinuxApp.sh`
- `docs/consumer-setup.md`
- `docs/compatibility-matrix.md`

## Current Behavior

The AppImage backend validation currently:

1. extracts the AppImage and validates its structure
2. launches the packaged AppImage with a generated marker path argument
3. requires the app to create that marker file

The sample Linux fixture is written to satisfy exactly that contract by
treating `argv[1]` as a smoke-marker output path.

## Why This Matters

Real GUI apps typically do one of these during smoke launch:

- launch with no arguments
- accept a document path to open
- accept app-specific automation flags

They do not usually create an arbitrary marker file merely because the
packaging harness passed a path as the first positional argument.

For such apps, the current choices are poor:

- disable smoke validation entirely, or
- add app-specific behavior solely to satisfy the packaging test harness

That makes the backend validation contract too fixture-shaped for general
downstream use.

## Reproduction

1. Use a real GNUstep GUI app whose normal launch contract is one of:
   - no arguments
   - document path
   - app-specific automation arguments
2. Package it with the AppImage backend.
3. Run backend validation with smoke enabled.
4. Observe that the backend assumes the app will create a marker file from the
   first positional argument rather than using a manifest-defined smoke mode.

## Expected Behavior

The AppImage backend should support multiple smoke strategies instead of a
single sample-fixture convention.

## Proposed Capability

Support smoke modes such as:

- `launch-only`
  - launch the packaged app and verify it starts successfully
- `open-file`
  - pass a staged sample document path and validate launch success
- `custom-arguments`
  - let the manifest define backend smoke arguments and environment
- `marker-file`
  - keep the current behavior as an explicit opt-in mode

The exact naming is flexible, but the manifest needs a generic way to express
how smoke validation should drive a real packaged app.

## Acceptance Criteria

- The current marker-file approach remains available for fixtures and consumers
  that want it.
- A generic GUI app can use backend smoke validation without adding custom
  marker-file code.
- The validation docs explain which smoke mode to use for:
  - GUI viewers and editors
  - document-based apps
  - app-specific automation hooks
- At least one sample manifest demonstrates a non-marker smoke mode.

## Downstream Impact

`ObjcMarkdown` is a real GUI document app. It can support automation if needed,
but it should not need to adopt a fixture-specific "write the smoke marker path
from argv[1]" convention just to participate in packager validation.

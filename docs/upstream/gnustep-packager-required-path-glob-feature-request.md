# gnustep-packager Feature Request: Allow Glob Patterns in `validation.smoke.requiredPaths`

## Summary

The current `requiredPaths` validation model appears to require exact literal
paths. That makes versioned GNUstep bundle validation awkward on Windows,
because bundle names can legitimately change across runtime updates, for example:

- `runtime/lib/GNUstep/Bundles/libgnustep-back-031.bundle/...`
- `runtime/lib/GNUstep/Bundles/libgnustep-back-032.bundle/...`

## Problem

Downstream manifests currently need to hardcode a specific backend bundle
version. That creates two bad options:

- lock validation to one exact backend version, which is brittle
- avoid validating the versioned path directly, which weakens smoke coverage

For GNUstep packaging, versioned bundle names are a normal packaging reality.
The manifest language should not force callers to choose between brittleness and
under-validation.

## Requested Feature

Allow glob-style entries inside `validation.smoke.requiredPaths`, for example:

```json
{
  "validation": {
    "smoke": {
      "requiredPaths": [
        "runtime/lib/GNUstep/Bundles/libgnustep-back-*.bundle/libgnustep-back-*.dll",
        "runtime/lib/GNUstep/Themes/*.theme/*.dll"
      ]
    }
  }
}
```

## Expected Semantics

- a glob entry succeeds when at least one path matches
- a glob entry fails when no paths match
- diagnostics should print the original pattern plus the matched paths, or note
  that no path matched

## Why This Matters

This would make manifest validation:

- more robust across GNUstep runtime upgrades
- more expressive for bundles, plugins, themes, and generated artifacts
- less likely to break on routine runtime-version changes

It would also reduce downstream pressure to hardcode internal runtime version
suffixes into long-lived manifests.

## Suggested Acceptance Test

Given a staged runtime containing:

- `runtime/lib/GNUstep/Bundles/libgnustep-back-032.bundle/libgnustep-back-032.dll`

And a manifest containing:

```json
"runtime/lib/GNUstep/Bundles/libgnustep-back-*.bundle/libgnustep-back-*.dll"
```

Expected result:

- smoke validation passes
- diagnostics report the matched concrete path

# Bug Report: reusable GitHub Actions workflow does not install the MSI prerequisites its docs imply

## Summary

The reusable GitHub Actions workflow for `backend: msi` currently installs only
`mingw-w64-clang-x86_64-clang`, but the documented MSI consumer model requires
a GNUstep-capable MSYS2 `CLANG64` environment. As written, the workflow is too
minimal for a real GNUstep app build and stage pipeline.

## Type

Bug

## Severity

High for downstream adoption. This blocks real GNUstep consumers from using the
promoted reusable workflow without copying and rewriting it.

## Observed In

- `gnustep-packager` commit: `d1edc0075311934d85e99c59783c74e62ce38bc8`
- downstream test case: `ObjcMarkdown`

## Affected Files

- `.github/workflows/package-gnustep-app.yml`
- `docs/github-actions.md`
- `docs/consumer-setup.md`
- `README.md`

## Current Behavior

The reusable workflow hardcodes this MSI package install set:

```yaml
install: >-
  mingw-w64-clang-x86_64-clang
```

The same repository documentation describes the MSI backend as targeting MSYS2
`CLANG64` GNUstep apps and says MSI consumers should build with that toolchain.

## Why This Is A Bug

A downstream reader can reasonably infer that the reusable workflow installs a
usable default MSI build environment for GNUstep apps. In practice it installs
only a C compiler and omits the broader GNUstep/MSYS2 toolchain that a real
consumer build commonly needs, including GNUstep packages and app-specific
dependencies such as `cmark`.

That mismatch turns the documented reusable workflow into a sample-only path.

## Reproduction

1. Create a downstream manifest whose `build` step runs a normal GNUstep app
   build under MSYS2 `CLANG64`.
2. Call `.github/workflows/package-gnustep-app.yml` with `backend: msi`.
3. Observe the build or stage step fail because the runner lacks the required
   GNUstep packages and related dependencies.

## Expected Behavior

One of these should be true:

1. The reusable workflow installs a real default MSI/GNUstep baseline that
   matches the documented consumer contract.
2. The reusable workflow exposes package-install inputs so downstream repos can
   declare the MSYS2 packages they need.

## Evidence

### Workflow

- `.github/workflows/package-gnustep-app.yml`
  - MSI install step currently installs only
    `mingw-w64-clang-x86_64-clang`

### Docs

- `docs/github-actions.md`
  - says MSI jobs install the MSYS2 `CLANG64` toolchain before packaging
- `docs/consumer-setup.md`
  - says MSI consumers should build with MSYS2 `CLANG64`
- `README.md`
  - describes the MSI backend as suitable for GNUstep apps built on MSYS2
    `CLANG64`

## Proposed Fix

Add an MSI package input such as `msys2-packages` and merge it with a sane
default GNUstep/MSYS2 baseline. The docs should then clearly distinguish:

- packages the reusable workflow installs by default
- packages the downstream app must add

## Acceptance Criteria

- A downstream GNUstep app can call the reusable workflow without copying the
  whole workflow just to install GNUstep prerequisites.
- The workflow docs describe the default package baseline precisely.
- The downstream example in the docs works for a real GNUstep app build, not
  only the packager sample fixture.

## Downstream Impact

`ObjcMarkdown` cannot rely on the reusable workflow as currently documented
because its Windows build requires a fuller MSYS2 `CLANG64` GNUstep
environment than the workflow currently provisions.

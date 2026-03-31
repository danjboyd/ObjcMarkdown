# Feature Request: make the reusable workflow configurable enough for real downstream GNUstep apps

## Summary

The reusable workflow currently hardcodes runner selection and a very small
backend-specific preflight. That is too rigid for real downstream apps that
need self-hosted runners, extra packaging inputs, or repo-specific host setup
before `build` and `stage`.

## Type

Feature request

## Priority

High for downstream adoption and future reuse across multiple GNUstep apps.

## Observed In

- `gnustep-packager` commit: `d1edc0075311934d85e99c59783c74e62ce38bc8`
- downstream test case: `ObjcMarkdown`

## Affected Files

- `.github/workflows/package-gnustep-app.yml`
- `docs/github-actions.md`
- `docs/local-ci-parity.md`
- `docs/consumer-setup.md`

## Current Behavior

The reusable workflow currently hardcodes:

- `backend: msi` -> `windows-latest`
- `backend: appimage` -> `ubuntu-latest`

It also hardcodes a very small preflight:

- MSI:
  - minimal MSYS2 package install
- AppImage:
  - `apt-get install squashfs-tools desktop-file-utils`

There is no caller-controlled hook for:

- overriding `runs-on`
- disabling or extending the built-in host setup
- running repo-specific preflight commands
- fetching extra packaging inputs before manifest resolution and pipeline
  execution

## Why This Matters

Real downstream GNUstep apps frequently need more than the sample-fixture host
shape. `ObjcMarkdown` is the first concrete test case and already needs:

- a self-hosted Linux GNUstep clang environment for AppImage packaging
- additional packaging inputs beyond the consumer repo itself
- more host setup than the current fixed preflight provides

This is not an exotic case. Many future GNUstep apps will need one or more of:

- self-hosted runners
- additional repositories or packaged assets
- distro- or org-specific bootstrap commands
- richer Windows/MSYS2 provisioning than the current default

## Requested Capability

Add reusable-workflow inputs for:

- runner selection per backend
- disabling or extending built-in host setup
- a caller-provided preflight command that runs after checkout but before
  manifest resolution and pipeline execution

## Suggested Shape

Illustrative inputs:

- `runs-on-msi`
- `runs-on-appimage`
- `skip-default-host-setup`
- `preflight-shell`
- `preflight-command`

An acceptable alternative would be a structured approach that achieves the same
practical result without those exact names.

## Design Constraints

The fix should preserve the repo's stated local/CI parity model:

- downstream-specific host prep happens in workflow preflight
- packaging still runs through `scripts/run-packaging-pipeline.ps1`
- the manifest and shared CLI remain the primary packaging contract

## Acceptance Criteria

- A downstream can use a self-hosted Linux GNUstep runner without forking the
  reusable workflow.
- A downstream can add repo-specific host/bootstrap logic without copying the
  whole workflow.
- The documented downstream example covers both:
  - a simple hosted-runner case
  - an advanced or self-hosted case
- Local/CI parity remains intact because the shared CLI still drives packaging.

## Downstream Impact

Without this flexibility, `ObjcMarkdown` would have to either:

- fork the reusable workflow immediately, or
- avoid it entirely and check out `gnustep-packager` as an external tool from a
  repo-owned workflow

That weakens the value proposition of the reusable workflow for future
downstream apps.

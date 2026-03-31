# Bug: MSI packaging records unresolved non-system DLLs but still emits an installer

## Summary
The MSI backend currently discovers unresolved runtime DLL imports during
closure analysis, records them in package metadata and logs, and then continues
building the MSI. That can produce a formally successful package even when the
tool already knows the packaged runtime is incomplete.

## Status
Addressed in the current `gnustep-packager` working tree on `2026-03-31`.

## Evidence
- `backends/msi/lib/msi.ps1` performs runtime-closure analysis and records
  missing non-system DLLs in an `unresolved` set:
  - lines 723-745 add unresolved imports when they cannot be found under the
    local install tree or configured `runtimeSearchRoots`
  - line 749 returns the unresolved list to the package step
- The package step receives that unresolved list and only logs it:
  - lines 1115-1122
- `docs/msi-runtime-policy.md` describes the current behavior as
  "best-effort DLL closure":
  - lines 42-50
- `docs/windows-msi-triage.md` treats unresolved dependencies as a normal
  triage artifact to inspect after packaging:
  - lines 29-36

## Why this is a bug
If the backend knows a non-system DLL imported by the launch entry, a runtime
seed, or an already-staged runtime binary cannot be resolved, it should not
silently produce a release artifact.

For a downstream app whose goal is "install on a clean Windows machine and run
without any preinstalled GNUstep runtime," unresolved non-system DLLs are a
packaging failure, not merely diagnostic metadata.

## Downstream impact
`ObjcMarkdown` currently stages its Windows runtime aggressively and explicitly
collects dependent DLLs before packaging. Its staging script also forces
dependency discovery for GNUstep backend and theme binaries:

- `scripts/windows/stage-runtime.sh`
  - dependency collection starts at lines 61-120
  - WinUX theme dependency collection is explicit at line 120

That downstream caution exists because shipping a runtime with missing DLLs is
not acceptable. `gnustep-packager` should enforce the same standard once it has
already detected an unresolved import.

## Expected behavior
One of these should be true:

- the MSI package step fails by default when unresolved non-system DLLs remain,
  or
- the backend exposes an explicit unresolved-dependency policy with a documented
  allowlist / ignore mechanism for known optional or delay-loaded imports

What should not happen is "package succeeded" while unresolved runtime imports
are only recorded in metadata.

## Proposed fix
Add a backend policy such as:

- `backends.msi.unresolvedDependencyPolicy: fail|warn`
- optional `backends.msi.ignoredRuntimeDependencies[]`

Recommended default:

- fail on unresolved non-system DLLs discovered from the launch entry,
  `payload.runtimeSeedPaths`, or already-staged runtime binaries

## Acceptance criteria
- A missing non-system DLL causes `package -Backend msi` to fail by default.
- Any override to continue despite unresolved DLLs is explicit in the manifest.
- The package metadata still records copied and unresolved dependencies for
  diagnostics.
- The triage docs explain how to use the ignore mechanism only for genuinely
  optional imports.

# gnustep-packager Upstream Issue Drafts

These documents capture downstream fit gaps discovered while evaluating
`ObjcMarkdown` as the first real consumer of `gnustep-packager`.

They are written as upstream-ready bug reports and feature requests so they can
be forwarded with minimal rewriting.

Observed against:

- `ObjcMarkdown` commit `fb7084117a8f7e2ab3e4cf4b3b15cd93036cc45e`
- `gnustep-packager` commit `d90569f68254ed6e1007b0e51c2c131c8ca95000`
- observation date: `2026-03-31`

Historical drafts:

- `bug-reusable-workflow-msi-prereqs.md`
- `bug-msi-runtime-closure-unresolved-dependencies-do-not-fail.md`
- `feature-reusable-workflow-runner-and-preflight-hooks.md`
- `feature-appimage-validation-configurable-smoke-modes.md`
- `feature-appimage-strict-runtime-closure-validation.md`
- `feature-launch-contract-conditional-environment-defaults.md`

Status as of `2026-03-31` follow-up:

- reusable workflow MSI prerequisites: addressed in `gnustep-packager`
- reusable workflow runner and preflight hooks: addressed in `gnustep-packager`
- configurable AppImage smoke modes: addressed in `gnustep-packager`
- MSI unresolved runtime dependencies now fail by default with explicit policy overrides
- AppImage strict runtime-closure validation is now implemented
- launch-contract conditional environment defaults are now implemented

These are internal tracking notes in this repo. The source of truth for fixes
should remain the upstream `gnustep-packager` repository.

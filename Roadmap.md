# ObjcMarkdown Roadmap

## Current Position

`ObjcMarkdown` is in a `0.1` source-first preview phase.

The current priority is not to chase every Markdown-editor feature at once. The priority is to make the existing GNUstep/Linux path solid, understandable, and pleasant to use.

## Near-Term Work

- stabilize the source editor, preview renderer, and split-view sync on real documents
- continue UI/theme polish so the viewer feels at home on modern GNUstep desktops
- improve packaging and release engineering:
  - Linux CI on the required clang/libobjc2/libdispatch stack
  - Windows MSI validation
  - eventual Linux app packaging
- keep CommonMark behavior strong before going deeper on GitHub-flavored extensions

## Phase 7: Windows Release Packaging and OCI Validation

Goal:
- make tagged releases produce installable Windows artifacts and validate them on a fresh OCI Windows environment

### Phase 7A: Stabilize And Commit The Release Baseline

Scope:
- commit the current local Windows/MSI/OCI workflow, script, and documentation changes before cutting any release tag
- reconcile docs and issue tracking so the OCI golden-image validation path is the documented source of truth
- make sure the release process is understandable from repo docs rather than session memory

### Phase 7B: Tagged CI Artifact Production

Scope:
- keep GitHub Actions responsible for building release artifacts on pushed version tags
- finish and verify the tag-triggered MSI and portable ZIP build flow
- optionally publish the MSI and ZIP to a GitHub Release page in addition to Actions artifacts
- document the exact tag-push workflow for creating a release build

### Phase 7C: OCI Clean-Machine Validation Automation

Scope:
- use the OCI golden-image workflow for clean-machine validation rather than depending on one long-lived mutable VM
- use helper scripts under `scripts/windows/` for VM launch, artifact copy, MSI install/smoke test, log collection, and VM teardown
- run the full tagged-release flow against a fresh OCI VM from the golden image
- collect validation logs and track any installer/runtime defects explicitly

Immediate next steps:
- `Phase 7B`: verified on `2026-03-26` with tag `v0.1.1-rc2`; decide separately whether to add GitHub Release-page asset publishing in addition to Actions artifacts
- `Phase 7C`: download the successful tagged CI artifact, repeat the clean-machine validation pass from that artifact, and codify the SSH-ingress hardening needed to keep fresh guests reachable during validation

Acceptance criteria:
- `Phase 7A`: the current Windows/MSI/OCI process is committed and documented coherently
- `Phase 7B`: pushing a tag such as `v0.1.0` produces a Windows MSI and portable ZIP in CI
- `Phase 7C`: the MSI is validated on a fresh OCI Windows VM launched from the golden image, with logs collected and follow-up defects tracked explicitly
- release tagging and validation are repeatable without ad hoc manual recovery steps

## Deferred Work

These are interesting, but they are not the current release gate:

- full WYSIWYG Markdown round-trip editing
- broad macOS release packaging
- large new feature areas that would dilute stabilization work

## Release Intent

- `0.1`: source build preview for GNUstep/Linux users
- next releases: stronger packaging, CI, and broader platform confidence without weakening the core editor/viewer path

## Internal Notes

Older milestone handoffs, validation notes, and working checklists now live under [docs/internal](docs/internal/README.md).

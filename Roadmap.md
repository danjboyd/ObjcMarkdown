# ObjcMarkdown Roadmap

## Current Position

`ObjcMarkdown` is in a `0.1` source-first preview phase.

The current priority is not to chase every Markdown-editor feature at once. The priority is to make the existing GNUstep/Linux path solid, understandable, and pleasant to use.

## Current Release Goal

The current release gate is narrower than the broader packaging work:

- pushing a Git tag should trigger GitHub Actions
- GitHub Actions should build a Linux AppImage and a Windows MSI from that tag
- those artifacts should be published to the matching GitHub Release so users can download them directly
- release publication should be repeatable without session-memory steps or manual backend assembly

The following are valuable, but they are not required to satisfy the current release gate:

- auto-update feeds and update-readiness validation
- OracleTestVMs handoff automation
- extra manual visual validation beyond the normal packaging smoke and clean-machine checks

## Near-Term Work

- stabilize the source editor, preview renderer, and split-view sync on real documents
- continue UI/theme polish so the viewer feels at home on modern GNUstep desktops
- improve packaging and release engineering:
  - Linux CI on the required clang/libobjc2/libdispatch stack
  - tagged GitHub Release publication for the Linux AppImage and Windows MSI
  - clean-machine validation on the externalized packaging path
  - release parity maintenance for AppImage and MSI packaging through `gnustep-packager`
- keep CommonMark behavior strong before going deeper on GitHub-flavored extensions

## Phase 7: Windows Release Packaging and OCI Validation

Goal:
- make tagged releases produce installable Windows artifacts, publish them to GitHub Releases, and validate them on a fresh OCI Windows environment

### Phase 7A: Stabilize And Commit The Release Baseline

Scope:
- commit the current local Windows/MSI/OCI workflow, script, and documentation changes before cutting any release tag
- reconcile docs and issue tracking so the OCI golden-image validation path is the documented source of truth
- make sure the release process is understandable from repo docs rather than session memory

### Phase 7B: Tagged CI Artifact Production

Scope:
- keep GitHub Actions responsible for building release artifacts on pushed version tags
- finish and verify the tag-triggered MSI and portable ZIP build flow
- publish the MSI and portable ZIP to the matching GitHub Release page, not only as Actions artifacts
- document the exact tag-push workflow for creating a release build

### Phase 7C: OCI Clean-Machine Validation Automation

Scope:
- use the OCI golden-image workflow for clean-machine validation rather than depending on one long-lived mutable VM
- use helper scripts under `scripts/windows/` for VM launch, artifact copy, MSI install/smoke test, log collection, and VM teardown
- run the full tagged-release flow against a fresh OCI VM from the golden image
- collect validation logs and track any installer/runtime defects explicitly

Immediate next steps:
- `Phase 7B`: verified on `2026-03-26` with tag `v0.1.1-rc2`
- `Phase 7C`: verified on `2026-03-26` against the CI-produced MSI from Actions run `23612901170`
- remaining release-gap check: keep GitHub Release publication mandatory in the documented flow, not optional
- optional release follow-up: do a short kept-VM manual visual pass when shortcut/icon/file-association polish needs explicit confirmation

Acceptance criteria:
- `Phase 7A`: the current Windows/MSI/OCI process is committed and documented coherently
- `Phase 7B`: pushing a tag such as `v0.1.0` produces a Windows MSI and portable ZIP in CI and publishes them to the corresponding GitHub Release
- `Phase 7C`: the MSI is validated on a fresh OCI Windows VM launched from the golden image, with logs collected and follow-up defects tracked explicitly
- release tagging and validation are repeatable without ad hoc manual recovery steps

## Phase 8: Externalize Linux and Windows Packaging Through gnustep-packager

Goal:
- make `gnustep-packager` the system of record for AppImage and MSI generation in local and CI release flows while shrinking `ObjcMarkdown` to consumer-owned build, stage, manifest, and validation glue

### Phase 8A: Define The Downstream Packaging Contract

Scope:
- add downstream packaging manifests for Linux AppImage and Windows MSI rather than relying on backend-specific scripts as the contract
- pin the initial integration to the currently audited `gnustep-packager` baseline (`bca864ff163e129100881145e017429fed155bf7`) until an explicit upstream release tag is chosen
- define the normalized staged payload shape for this repo:
  - `app/`
  - `runtime/`
  - `metadata/`
- decide which app-owned assets remain staged here:
  - icons
  - runtime notices
  - sample smoke documents if needed
  - Linux Adwaita theme input
  - Windows WinUX theme input
- express GNUstep theme defaults through manifest-driven launch policy instead of custom backend launchers:
  - Linux `GSTheme=Adwaita` with `ifUnset`
  - Windows `GSTheme=WinUXTheme` with `ifUnset`

### Phase 8B: Normalize Linux Staging And AppImage Parity

Scope:
- replace the current AppDir-producing Linux script with a stage script that emits only `app/`, `runtime/`, and `metadata/`
- stage the Linux private runtime closure required for stock-machine execution:
  - GNUstep libraries
  - GNUstep backend bundle
  - Adwaita theme payload
  - fontconfig data
  - glib schemas required by the packaged theme/runtime path
  - bundled `pandoc` payload if release behavior still requires built-in document conversion on end-user systems
- validate Linux packaging through `gnustep-packager` strict AppImage runtime-closure checks and smoke launch rather than `linuxdeploy`-specific logic
- keep Linux-specific preflight limited to host verification and preparing pinned theme input on the self-hosted GNUstep runner

### Phase 8C: Normalize Windows Staging And MSI Parity

Scope:
- replace the current install-tree/WiX-oriented Windows script with a stage script that emits only `app/`, `runtime/`, and `metadata/`
- stage the Windows private runtime closure required for stock-machine execution:
  - GNUstep runtime DLLs
  - project DLLs
  - `defaults.exe`
  - GNUstep bundles and support resources
  - WinUX theme payload
  - fontconfig data
  - installer icons and notices
- use the packager launcher contract rather than the repo-local launcher as the startup path
- pass MSI runtime closure under the new default failure policy so unresolved non-system DLLs stop packaging instead of leaking into release artifacts
- validate the packager-produced MSI against the existing clean-machine OCI path before removing the old implementation

### Phase 8D: GitHub Actions Cutover

Scope:
- replace backend-building logic in:
  - `linux-appimage.yml`
  - `windows-packaging.yml`
  with thin caller workflows that use the reusable `gnustep-packager` workflow
- keep release version/tag behavior in this repo but pass the resolved version into the reusable workflow through `package-version`
- publish the resulting AppImage, `.zsync`, MSI, and any release-sidecar metadata to the matching GitHub Release as part of the tagged flow
- configure the Linux caller to use:
  - the existing self-hosted GNUstep runner labels
  - `skip-default-host-setup: true`
  - a repo-owned preflight command for GNUstep host verification and Adwaita theme checkout
- configure the Windows caller to use:
  - `windows-latest`
  - the packager MSI baseline
  - `msys2-packages` for app-specific dependencies such as `mingw-w64-clang-x86_64-cmark`
- keep CI validation enabled for both backends and preserve any extra app-specific smoke we still need beyond the shared packager validation

### Phase 8E: External-Only Backend Packaging Cleanup

Scope:
- perform a parity pass on tagged releases so the packager-produced AppImage and MSI match current release expectations for launch, theming, runtime closure, and artifact naming
- remove backend assembly code from this repo after parity is proven:
  - `linuxdeploy` download/use logic
  - custom AppDir assembly logic
  - custom `AppRun` generation
  - custom MSI/WiX build path
  - custom top-level Windows launcher source used only for packaging
- keep only the consumer-owned pieces that `gnustep-packager` intentionally requires downstream repos to own:
  - manifests
  - build scripts
  - normalized stage scripts
  - small preflight helpers
  - any app-specific validation that is truly product-specific rather than backend-generic
- update repo docs so external `gnustep-packager` usage is the documented source of truth for release packaging

Immediate next steps:
- `Phase 8A`: implemented on `2026-04-01` with downstream Linux and Windows manifests under `packaging/`, normalized `app/` + `runtime/` + `metadata/` staging, and manifest-driven theme defaults
- `Phase 8B`: verified on `2026-04-01` by building and validating `dist/packaging/linux/packages/ObjcMarkdown-0.1.1-rc2-linux-x86_64.AppImage` through `gnustep-packager` with smoke launch enabled
- `Phase 8C`: repo cutover completed on `2026-04-01`; Windows manifest, staging, workflow, and OCI validation now target `gnustep-packager`, with the next Windows-host MSI build plus OCI run serving as the parity reconfirmation pass
- `Phase 8D`: implemented on `2026-04-01` by replacing repo-local backend assembly in `linux-appimage.yml` and `windows-packaging.yml` with reusable `gnustep-packager` workflow calls pinned to `bca864ff163e129100881145e017429fed155bf7`
- `Phase 8E`: implemented on `2026-04-01` by deleting legacy backend assembly code and keeping only manifests, build/stage scripts, preflight helpers, and app-specific validation glue in this repo

Acceptance criteria:
- `Phase 8A`: the repo contains committed downstream manifests and a documented normalized staging contract for both target platforms
- `Phase 8B`: the Linux AppImage is built by `gnustep-packager`, includes the private GNUstep runtime plus Adwaita theming, and passes strict runtime-closure validation without depending on host GNUstep libraries
- `Phase 8C`: the Windows MSI is built by `gnustep-packager`, includes the private GNUstep runtime plus WinUX theming, and passes clean-machine validation without relying on a shared preinstalled `C:\\clang64` runtime
- `Phase 8D`: pushing a release tag produces the AppImage and MSI through the reusable `gnustep-packager` workflow and publishes them to the matching GitHub Release rather than only to workflow artifacts
- `Phase 8E`: backend packaging implementation is externalized; this repo retains only consumer build/stage/manifests and any genuinely app-specific validation hooks

## Phase 9: Post-Release Hardening For Auto-Update And OracleTestVMs

Goal:
- extend the `gnustep-packager` integration to cover auto-update delivery and validation for Linux AppImage and Windows MSI releases, then use `OracleTestVMs` to stand up reproducible test machines with preloaded sample Markdown content for manual verification after the core tag-to-GitHub-Release packaging flow is complete

### Phase 9A: Define Auto-Update Release Policy

Scope:
- document the release-channel and update-feed expectations that `ObjcMarkdown` will support through `gnustep-packager`
- adopt AppImage auto-update best practices for Linux so shipped artifacts can discover and apply updates through the standard AppImage update path
- adopt Windows MSI auto-update best practices supported by `gnustep-packager`, including how upgrade codes, product-version progression, and installer replacement behavior are managed across releases
- decide which release metadata stays owned by this repo versus generated by the packager
- document the minimum invariants required so future tagged releases remain updateable instead of silently breaking upgrade paths

### Phase 9B: Wire Auto-Update Metadata Into Linux and Windows Packaging

Scope:
- extend the downstream Linux AppImage manifest and release flow so auto-update metadata is emitted consistently on tagged builds
- extend the downstream Windows MSI manifest and release flow so upgrade-aware MSI metadata is emitted consistently on tagged builds
- verify that release artifacts published from this repo contain the fields and sidecar metadata required by the chosen update mechanisms
- keep the packaging contract explicit so downstream validation can assert update readiness, not just first-install success

### Phase 9C: OracleTestVMs Linux Validation Environment

Scope:
- use the `OracleTestVMs` sister repo to provision a fresh Linux test VM for AppImage validation
- preload the Linux VM with a small set of sample Markdown documents that exercise headings, lists, links, code blocks, tables if supported, and larger scrolling documents
- copy in the produced AppImage plus any update-related artifacts needed to validate first install and follow-up update behavior
- automate enough VM setup that the Linux machine can be handed off for manual testing with predictable connection instructions

### Phase 9D: OracleTestVMs Windows Build And Test Environments

Scope:
- use the `OracleTestVMs` sister repo to provision two separate Windows VMs:
  - a Windows build VM for producing or reproducing the MSI in a packaging-capable environment
  - a clean Windows test VM for validating first install, upgrade behavior, and runtime launch on a machine that does not share the build environment
- preload the Windows test VM with the MSI under test and a matching set of sample Markdown documents
- keep the clean Windows test VM isolated from build-tool contamination so MSI validation remains meaningful
- automate enough VM setup that the Windows test machine can be handed off for manual testing with predictable connection instructions

### Phase 9E: Operator Handoff And Manual Verification Workflow

Scope:
- define the exact operator instructions for connecting to each provisioned VM once `OracleTestVMs` has launched it
- document where the sample Markdown files are placed on Linux and Windows so manual smoke testing starts immediately after login
- document the manual test flow for:
  - opening sample files
  - confirming theme/runtime correctness
  - validating AppImage update behavior on Linux
  - validating MSI install and upgrade behavior on Windows
- keep the handoff instructions short enough to use directly during release validation sessions

Immediate next steps:
- `Phase 9A`: align with `gnustep-packager` on the exact AppImage and MSI auto-update capabilities we can consume without repo-local update logic
- `Phase 9B`: add the missing Linux and Windows manifest/release metadata needed for update-aware artifacts
- `Phase 9C`: stand up a Linux VM through `OracleTestVMs`, preload sample Markdown fixtures, and capture the exact connection steps
- `Phase 9D`: stand up separate Windows build and Windows clean-test VMs through `OracleTestVMs`, preload the clean-test VM with sample Markdown fixtures, and capture the exact connection steps
- `Phase 9E`: write the final operator-facing instructions for connecting to each VM and exercising the AppImage and MSI manually

Acceptance criteria:
- `Phase 9A`: the repo documents a stable auto-update policy for AppImage and MSI releases that is compatible with `gnustep-packager`
- `Phase 9B`: tagged Linux and Windows release artifacts include the required update metadata and pass update-readiness checks in addition to packaging checks
- `Phase 9C`: a reproducible Linux VM can be launched from `OracleTestVMs`, contains sample Markdown files, and is ready for manual AppImage validation with documented connection steps
- `Phase 9D`: separate Windows build and clean-test VMs can be launched from `OracleTestVMs`, the clean-test VM contains sample Markdown files, and the MSI can be validated there without relying on build-machine state
- `Phase 9E`: the operator can follow repo-documented instructions to connect to the Linux VM and the Windows test VM and perform manual validation of AppImage and MSI behavior

## Deferred Work

These are interesting, but they are not the current release gate:

- full WYSIWYG Markdown round-trip editing
- Phase 9 auto-update and OracleTestVMs follow-on work
- broad macOS release packaging
- large new feature areas that would dilute stabilization work

## Release Intent

- `0.1`: source build preview for GNUstep/Linux users
- next releases: stronger packaging, CI, and broader platform confidence without weakening the core editor/viewer path

## Internal Notes

Older milestone handoffs, validation notes, and working checklists now live under [docs/internal](docs/internal/README.md).

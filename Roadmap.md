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

## Phase 7: Windows Release Packaging and Clean-Machine Validation

Goal:
- make tagged releases produce installable Windows artifacts, publish them to GitHub Releases, and validate them on a fresh `OracleTestVMs` Windows environment, with libvirt-backed leases as the default backend

### Phase 7A: Stabilize And Commit The Release Baseline

Scope:
- commit the current local Windows/MSI validation workflow, script, and documentation changes before cutting any release tag
- reconcile docs and issue tracking so the `OracleTestVMs` validation path is the documented source of truth
- make sure the release process is understandable from repo docs rather than session memory

### Phase 7B: Tagged CI Artifact Production

Scope:
- keep GitHub Actions responsible for building release artifacts on pushed version tags
- finish and verify the tag-triggered MSI and portable ZIP build flow
- publish the MSI and portable ZIP to the matching GitHub Release page, not only as Actions artifacts
- document the exact tag-push workflow for creating a release build

### Phase 7C: Clean-Machine Validation Automation

Scope:
- use `OracleTestVMs` for clean-machine validation rather than depending on one long-lived mutable VM
- prefer libvirt-backed Windows leases for reproducible build/test handoff
- use helper scripts under `scripts/windows/` for VM launch, artifact copy, MSI install/smoke test, log collection, and VM teardown
- run the full tagged-release flow against a fresh Windows VM from the supported `OracleTestVMs` backend
- collect validation logs and track any installer/runtime defects explicitly

Immediate next steps:
- `Phase 7B`: verified on `2026-03-26` with tag `v0.1.1-rc2`
- `Phase 7C`: verified on `2026-03-26` against the CI-produced MSI from Actions run `23612901170`
- remaining release-gap check: keep GitHub Release publication mandatory in the documented flow, not optional
- optional release follow-up: do a short kept-VM manual visual pass when shortcut/icon/file-association polish needs explicit confirmation

Acceptance criteria:
- `Phase 7A`: the current Windows/MSI validation process is committed and documented coherently
- `Phase 7B`: pushing a tag such as `v0.1.0` produces a Windows MSI and portable ZIP in CI and publishes them to the corresponding GitHub Release
- `Phase 7C`: the MSI is validated on a fresh `OracleTestVMs` Windows VM, with libvirt-backed leases preferred, logs collected, and follow-up defects tracked explicitly
- release tagging and validation are repeatable without ad hoc manual recovery steps

## Phase 8: Externalize Linux and Windows Packaging Through gnustep-packager

Goal:
- make `gnustep-packager` the system of record for AppImage and MSI generation in local and CI release flows while shrinking `ObjcMarkdown` to consumer-owned build, stage, manifest, and validation glue

### Phase 8A: Define The Downstream Packaging Contract

Scope:
- add downstream packaging manifests for Linux AppImage and Windows MSI rather than relying on backend-specific scripts as the contract
- repin the initial integration from the earlier audited `gnustep-packager` baseline (`bca864ff163e129100881145e017429fed155bf7`) to a current upstream commit that includes:
  - manifest-driven host dependency provisioning
  - reusable dependency profiles such as `gnustep-cmark`
  - declarative packaged defaults
  - semantic packaged/install-result assertions including `bundled-theme`
- define the normalized staged payload shape for this repo:
  - `app/`
  - `runtime/`
  - `metadata/`
- decide which app-owned assets remain staged here:
  - icons
  - runtime notices
  - sample smoke documents if needed
  - Linux Adwaita theme input
  - Windows WinUI theme input
- move app-specific packaging intent into the manifest rather than workflow-only overrides:
  - add `gnustep-cmark` to the manifest profile stack where appropriate
  - declare default themes through `packagedDefaults.defaultTheme`
  - use semantic package/install assertions where they reduce repo-local path coupling
- express GNUstep theme defaults through manifest-driven launch policy instead of custom backend launchers:
  - Linux `GSTheme=Adwaita` with `ifUnset`
  - Windows `GSTheme=WinUITheme` with `ifUnset`

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
- keep Linux-specific preflight limited to app-owned setup, primarily preparing the pinned Adwaita theme input, while `gnustep-packager` owns hosted GNUstep toolchain bootstrap through `gnustep-cli-new`

### Phase 8C: Normalize Windows Staging And MSI Parity

Scope:
- replace the current install-tree/WiX-oriented Windows script with a stage script that emits only `app/`, `runtime/`, and `metadata/`
- stage the Windows private runtime closure required for stock-machine execution:
  - GNUstep runtime DLLs
  - project DLLs
  - `defaults.exe`
  - GNUstep bundles and support resources
  - WinUI theme payload
  - fontconfig data
  - installer icons and notices
- use the packager launcher contract rather than the repo-local launcher as the startup path
- pass MSI runtime closure under the new default failure policy so unresolved non-system DLLs stop packaging instead of leaking into release artifacts
- declare app-specific MSYS2 host dependencies in the manifest instead of relying on workflow-only package inputs
- validate the packager-produced MSI against the existing clean-machine validation path before removing the old implementation

### Phase 8D: GitHub Actions Cutover

Scope:
- replace backend-building logic in:
  - `linux-appimage.yml`
  - `windows-packaging.yml`
  with thin caller workflows that use the reusable `gnustep-packager` workflow
- keep release version/tag behavior in this repo but pass the resolved version into the reusable workflow through `package-version`
- publish the resulting AppImage, `.zsync`, MSI, and any release-sidecar metadata to the matching GitHub Release as part of the tagged flow
- configure the Linux caller to use:
  - GitHub-hosted execution through the reusable `gnustep-packager` workflow
  - the packager-owned `gnustep-cli-new` bootstrap and smoke-validation path
  - a repo-owned preflight command only for app-specific setup such as Adwaita theme checkout
- configure the Windows caller to use:
  - `windows-latest`
  - the packager MSI baseline and hosted `gnustep-cli-new` MSYS2/clang64 toolchain contract
- keep the hosted runner/toolchain dependency explicit through manifest inputs, workflow pins, and uploaded `gnustep-cli-new` diagnostics rather than relying on a hand-maintained self-hosted runner
- remove workflow-only Windows package overrides once the manifest carries the same contract
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
- `Phase 8C`: repo cutover completed on `2026-04-01`; Windows manifest, staging, workflow, and clean-machine validation now target `gnustep-packager`, with the next Windows-host MSI build plus `OracleTestVMs` run serving as the parity reconfirmation pass
- `Phase 8D`: implemented on `2026-04-01` by replacing repo-local backend assembly in `linux-appimage.yml` and `windows-packaging.yml` with reusable `gnustep-packager` workflow calls pinned to `bca864ff163e129100881145e017429fed155bf7`
- `Phase 8E`: implemented on `2026-04-01` by deleting legacy backend assembly code and keeping only manifests, build/stage scripts, preflight helpers, and app-specific validation glue in this repo
- `Phase 8F`: second repin pass implemented locally on `2026-04-21` by moving both reusable workflow callers to audited `gnustep-packager` commit `3c10f1a2c8f976cc30aaaa4f85f6a14b74ebb562` and passing explicit `packager-repository`/`packager-ref` checkout inputs required by the current reusable workflow
- `Phase 8G`: first manifest/consumer-contract pass implemented locally on `2026-04-21`; Linux host dependencies are manifest-owned, Windows/Linux scripts resolve GNUstep/MSYS2 locations from the packager-provided environment, and app-specific preflight no longer validates the host GNUstep installation
- `Phase 8I`: first hosted runner/toolchain adoption pass implemented locally on `2026-04-21`; ObjcMarkdown now expects `gnustep-packager` to consume the published `gnustep-cli-new` release manifest/artifacts rather than depending on repo-local runner preparation
- `Phase 8B/8I`: hosted Linux AppImage packaging passed on `2026-04-21` in GitHub Actions run `24743212445` after adapting Linux staging to the managed `gnustep-cli-new` `Local/Library` runtime layout, treating absent PreferencePanes payloads as optional, and switching AppImage smoke validation to the packager-supported marker-file mode for headless CI
- `Phase 8J`: upstream bounded Windows bootstrap diagnostics were added to `gnustep-packager` commit `3c10f1a2c8f976cc30aaaa4f85f6a14b74ebb562` and consumed by the ObjcMarkdown packaging workflows on `2026-04-21`; hosted run `24746538617` proved the diagnostics path by uploading setup/build/run logs instead of hanging, and hosted run `24747049925` then passed the MSI bootstrap step with the direct `HelloPackager.exe` smoke
- `Phase 8H`: Windows hosted MSI validation is now past bootstrap as of `2026-04-21`; run `24747049925` failed in app packaging because the hosted workspace lacked `plugins-themes-winuitheme`, run `24747383333` confirmed the required WinUITheme input is fetched, run `24747752773` exposed an app-side MSYS path conversion bug, run `24748075413`/`24748308894` exposed GNUstep makefile-root assumptions, and run `24748570291` reached real WinUITheme compilation before hitting GNUstep's baked `/clang64/bin/clang` compiler path; the current app-side pass keeps theme build output in the workflow log, skips optional theme fetches unless explicitly enabled, carries the prepared user theme root into both build and stage steps, resolves Windows paths through the active MSYS2 shell's `cygpath`, exports `GNUSTEP_MAKEFILES` to the managed `gnustep-cli-new` makefile path, and overrides compiler variables to the managed clang/clang++ binaries
- remaining execution gap:
  - complete one fresh validated Windows MSI rebuild through the normal reusable workflow path now that the bootstrap diagnostics gap is patched upstream
  - rerun clean-machine Windows validation through `OracleTestVMs` against the fresh MSI and portable ZIP artifacts
  - confirm a release tag now produces and publishes both artifacts end-to-end

Acceptance criteria:
- `Phase 8A`: the repo contains committed downstream manifests and a documented normalized staging contract for both target platforms
- `Phase 8B`: the Linux AppImage is built by `gnustep-packager`, includes the private GNUstep runtime plus Adwaita theming, and passes strict runtime-closure validation without depending on host GNUstep libraries
- `Phase 8C`: the Windows MSI is built by `gnustep-packager`, includes the private GNUstep runtime plus WinUI theming, and passes clean-machine validation without relying on a shared preinstalled `C:\\clang64` runtime
- `Phase 8D`: pushing a release tag produces the AppImage and MSI through the reusable `gnustep-packager` workflow and publishes them to the matching GitHub Release rather than only to workflow artifacts
- `Phase 8E`: backend packaging implementation is externalized; this repo retains only consumer build/stage/manifests and any genuinely app-specific validation hooks

## Remaining Release Subphases

These are the remaining execution subphases required to satisfy the current
release gate with the newer `gnustep-packager` contract.

### Phase 8F: Repin To The Current gnustep-packager Contract

Scope:
- update both reusable workflow callers to the current audited `gnustep-packager` commit `3c10f1a2c8f976cc30aaaa4f85f6a14b74ebb562`
- consume the newer upstream contract for:
  - host dependency provisioning
  - `gnustep-cmark`
  - `packagedDefaults.defaultTheme`
  - semantic packaged/install-result assertions including `bundled-theme`
- keep the pin explicit in repo docs so release builds remain reproducible

Acceptance criteria:
- both packaging workflows are pinned to the newer upstream commit
- both packaging workflows pass explicit packager checkout inputs so the reusable workflow checks out `gnustep-packager`, not the caller repository
- the repo no longer depends on obsolete workflow assumptions from the older baseline
- local build, test, manifest resolution, and host setup-plan checks pass before hosted workflow validation

### Phase 8G: Manifest Contract Migration

Scope:
- update the Windows and Linux manifests to move app-specific packaging intent into the manifest
- add reusable host dependency profiles and/or explicit host dependency declarations where still needed
- remove Windows workflow-level package overrides once the manifest owns the same dependency contract
- adopt declarative packaged defaults and semantic package/install assertions where they reduce repo-local path coupling
- keep build and stage scripts toolchain-location aware so they work with the packager-provided GNUstep/MSYS2 roots instead of hardcoded `/usr/GNUstep` or `C:\msys64` assumptions

Acceptance criteria:
- the manifests, not the workflows, carry app-specific packaging requirements such as `cmark` and default theme intent
- downstream packaging correctness lives primarily in the packager contract rather than repo-local workflow overrides
- app-owned scripts source GNUstep from `GNUSTEP_MAKEFILES`/`GP_GNUSTEP_CLI_ROOT` or equivalent packager-provided roots before falling back to developer-machine defaults

### Phase 8H: Fresh Windows MSI Rebuild And Validation On The Normal Path

Scope:
- rebuild the MSI and portable ZIP through the normal reusable workflow path after the manifest/workflow migration
- confirm the packaged payload includes the expected WinUI theme/default-theme behavior and required runtime closure
- rerun clean-machine validation against the fresh artifacts and capture any remaining defects explicitly

Acceptance criteria:
- a fresh MSI and portable ZIP are produced from the normal reusable workflow path
- clean-machine validation passes against those artifacts

### Phase 8I: Hosted Runner Toolchain Adoption Through gnustep-cli-new

Scope:
- consume `gnustep-cli-new` through the `gnustep-packager` hosted bootstrap path rather than through ObjcMarkdown-owned runner preparation
- keep ObjcMarkdown build, stage, and theme-preparation scripts compatible with the toolchain locations exposed by that bootstrap path
- require hosted workflow logs to upload enough `gnustep-cli-new` diagnostics to distinguish app build/stage failures from bootstrap/toolchain failures
- keep the chosen hosted runner path documented so release builds do not depend on session memory or hand-maintained runner state

Acceptance criteria:
- the Linux AppImage workflow starts and finishes on GitHub-hosted infrastructure using the packager-owned `gnustep-cli-new` contract
- the Windows MSI workflow relies on the same documented bootstrap contract rather than ad hoc machine preparation
- uploaded diagnostics make the toolchain provenance and validation result reviewable after each hosted run
- the hosted runner model is documented and repeatable

Current status:
- Linux satisfies this phase as of run `24743212445`.
- Windows has consumed the bounded bootstrap diagnostics pin, but it still needs a fresh hosted MSI run before this phase is fully proven on both platforms.

### Phase 8J: Windows Hosted Bootstrap Diagnostics And Timeout

Scope:
- update or consume an upstream `gnustep-packager`/`gnustep-cli-new` change that makes the Windows MSI bootstrap step bounded and diagnosable
- ensure the reusable workflow uploads partial `gnustep-cli-new` host context, selection, download, extraction, and smoke logs even when the bootstrap does not complete
- rerun the Windows MSI workflow on the current ObjcMarkdown branch and classify the first actionable failure after bootstrap, if any

Current status:
- upstream `gnustep-packager` commit `3c10f1a2c8f976cc30aaaa4f85f6a14b74ebb562` bounds the hosted Windows bootstrap step, captures stdout/stderr into diagnostics, kills the bootstrap process tree on timeout, and smokes the generated Windows `HelloPackager.exe` directly until the published `gnustep-cli-new` Windows CLI artifact is refreshed
- ObjcMarkdown's Linux and Windows packaging workflows are pinned to that commit; hosted runs `24747049925` and `24747383333` passed the Windows bootstrap gate and moved the active blocker to app-side hosted theme packaging and staging

Acceptance criteria:
- a hosted Windows bootstrap failure produces uploaded diagnostics and a bounded failure instead of an indefinite in-progress workflow step
- a successful hosted Windows bootstrap proceeds into ObjcMarkdown preflight, build, stage, MSI package, and smoke validation
- the resulting evidence is enough to either close Phase 8H or create a precise app-side packaging defect

### Phase 8K: End-To-End Tagged Release Confirmation

Scope:
- push a release tag through the updated Windows and Linux packaging workflows
- confirm both artifacts are built, uploaded, and published to the matching GitHub Release
- verify that the release flow is repeatable without ad hoc operator recovery

Acceptance criteria:
- one real tag produces and publishes both the AppImage and MSI successfully
- the documented release gate is satisfied end-to-end

## Phase 9: Post-Release Hardening For Auto-Update And OracleTestVMs

Goal:
- extend the `gnustep-packager` integration to cover auto-update delivery and validation for Linux AppImage and Windows MSI releases, then use libvirt-backed `OracleTestVMs` leases to stand up reproducible test machines with preloaded sample Markdown content for manual verification after the core tag-to-GitHub-Release packaging flow is complete

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
- use the `OracleTestVMs` sister repo to provision a fresh Linux test VM for AppImage validation, preferring libvirt-backed Debian leases
- preload the Linux VM with a small set of sample Markdown documents that exercise headings, lists, links, code blocks, tables if supported, and larger scrolling documents
- copy in the produced AppImage plus any update-related artifacts needed to validate first install and follow-up update behavior
- automate enough VM setup that the Linux machine can be handed off for manual testing with predictable connection instructions

### Phase 9D: OracleTestVMs Windows Build And Test Environments

Scope:
- use the `OracleTestVMs` sister repo to provision two separate Windows VMs:
  - a Windows build VM for producing or reproducing the MSI in a packaging-capable environment
  - a clean Windows test VM for validating first install, upgrade behavior, and runtime launch on a machine that does not share the build environment
- prefer libvirt-backed Windows leases for both machines when available
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

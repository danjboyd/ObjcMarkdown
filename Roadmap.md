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
- `Phase 7B`: verified on `2026-03-26` with tag `v0.1.1-rc2`
- `Phase 7C`: verified on `2026-03-26` against the CI-produced MSI from Actions run `23612901170`
- optional release follow-up: publish tagged MSI and ZIP assets to a GitHub Release page in addition to Actions artifacts
- optional release follow-up: do a short kept-VM manual visual pass when shortcut/icon/file-association polish needs explicit confirmation

Acceptance criteria:
- `Phase 7A`: the current Windows/MSI/OCI process is committed and documented coherently
- `Phase 7B`: pushing a tag such as `v0.1.0` produces a Windows MSI and portable ZIP in CI
- `Phase 7C`: the MSI is validated on a fresh OCI Windows VM launched from the golden image, with logs collected and follow-up defects tracked explicitly
- release tagging and validation are repeatable without ad hoc manual recovery steps

## Phase 8: Externalize Linux and Windows Packaging Through gnustep-packager

Goal:
- make `gnustep-packager` the system of record for AppImage and MSI generation in local and CI release flows while shrinking `ObjcMarkdown` to consumer-owned build, stage, manifest, and validation glue

### Phase 8A: Define The Downstream Packaging Contract

Scope:
- add downstream packaging manifests for Linux AppImage and Windows MSI rather than relying on backend-specific scripts as the contract
- pin the initial integration to the currently audited `gnustep-packager` baseline (`fb29ee4ef61ecfcc8e7e0c8ee0b690883351324c`) until an explicit upstream release tag is chosen
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
- start with `Phase 8A` by creating a `packaging/` layout and drafting separate Linux and Windows manifests
- preserve the current release workflows until both normalized staging paths work locally through `gnustep-packager`
- treat the current upstream `main` commit `fb29ee4ef61ecfcc8e7e0c8ee0b690883351324c` as the initial pinned integration target unless it is replaced by a release tag before cutover
- keep the OCI validation flow from Phase 7 as the clean-machine confirmation path for the packager-produced MSI

Acceptance criteria:
- `Phase 8A`: the repo contains committed downstream manifests and a documented normalized staging contract for both target platforms
- `Phase 8B`: the Linux AppImage is built by `gnustep-packager`, includes the private GNUstep runtime plus Adwaita theming, and passes strict runtime-closure validation without depending on host GNUstep libraries
- `Phase 8C`: the Windows MSI is built by `gnustep-packager`, includes the private GNUstep runtime plus WinUX theming, and passes clean-machine validation without relying on a shared preinstalled `C:\\clang64` runtime
- `Phase 8D`: pushing a release tag produces the AppImage and MSI through the reusable `gnustep-packager` workflow rather than repo-local backend assembly
- `Phase 8E`: backend packaging implementation is externalized; this repo retains only consumer build/stage/manifests and any genuinely app-specific validation hooks

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

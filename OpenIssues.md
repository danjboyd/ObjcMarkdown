# Open Issues

## 2) Feasibility: Full WYSIWYG Markdown editor

- **Status**: Open
- **Opened On**: 2026-02-13
- **Area**: Viewer / Editor architecture / Markdown round-trip
- **Description**: Evaluate and plan implementation of a full WYSIWYG Markdown editor where visual edits reliably serialize back to Markdown without destructive rewrites.
- **Current State**:
  - Viewer text surface is read-only.
  - Rendering pipeline remains one-way (`markdown -> NSAttributedString`) with no general attributed-edit-to-Markdown serializer.
- **Feasibility Assessment**:
  - Estimated difficulty: high (roughly 8/10).
  - Expected effort: multi-month for robust full-fidelity WYSIWYG.
- **Notes**:
  - Keep this as a subsequent phase after hybrid editor hardening.

## 4) Phase-2 renderer syntax-highlighting architecture (language breadth)

- **Status**: Open
- **Opened On**: 2026-02-16
- **Area**: Renderer / Syntax highlighting / Dependency strategy
- **Description**: Decide long-term architecture for multi-language renderer highlighting beyond phase-1 heuristics.
- **Current State**:
  - Phase-1 renderer syntax highlighting is shipped with Tree-sitter availability gating.
- **Open Questions**:
  - Bespoke tokenizer expansion vs deeper Tree-sitter parser integration per language.
  - Packaging/runtime behavior when Tree-sitter libraries or grammars are unavailable.
  - Performance and fallback UX expectations at large document sizes.
- **Notes**:
  - Treat as post-phase-1 follow-on work, not a blocker for current stabilization.

## 5) Inline HTML rendering support (deferred to Phase 2)

- **Status**: Open
- **Opened On**: 2026-02-18
- **Area**: Renderer / HTML policy / Preview fidelity
- **Description**: Inline and block HTML are currently handled as literal text (or dropped via policy), not rendered as rich HTML in preview.
- **Current State**:
  - Default parsing policy is `RenderAsText` for inline and block HTML.
  - HTML import/export is supported through Pandoc when available.
- **Planned Work**:
  - Design a safe rendering strategy for inline/block HTML (likely constrained subset + sanitization).
  - Define fallback behavior when markup is unsupported.
  - Add dedicated renderer tests for allowed/blocked HTML rendering paths.
- **Notes**:
  - Explicitly scheduled for Phase 2 work in `Roadmap.md`.

## 8) Investigate Sombre theme failure on Windows (feasibility + fix path)

- **Status**: Open
- **Opened On**: 2026-02-19
- **Area**: Windows runtime / GNUstep theming / Compatibility
- **Description**: Determine why `GSTheme=Sombre` does not produce a usable window on Windows and assess whether a practical fix is feasible.
- **Current State**:
  - Under Windows GNUstep + MSYS2, launching with Sombre can start the process but fail to present a normal main window.
  - Observed runtime exception during launch path under Sombre:
    - `NSInvalidArgumentException` with `NSConstantString ... forwardInvocation: ... hash`.
  - App remains usable under `WinUXTheme`, so issue appears theme/runtime specific rather than core app startup.
- **Investigation Goals**:
  - Reproduce in a minimal GNUstep app with and without Sombre to isolate theme plugin vs app interaction.
  - Identify whether failure is caused by Sombre plugin code, GNUstep backend incompatibility on Windows, or app-side assumptions.
  - Establish workaround options (theme fallback, selective feature disable) if full Sombre support is not feasible.
- **Notes**:
  - Outcome should include a go/no-go feasibility decision and recommended implementation path.

## 9) Automated Linux Flatpak packaging pipeline (GNUstep runtime included)

- **Status**: Open
- **Opened On**: 2026-02-19
- **Area**: Release engineering / Linux packaging / CI-CD
- **Description**: Build automated GitHub pipelines that produce a Flatpak for `MarkdownViewer` that runs on a stock Linux desktop without requiring users to manually install GNUstep or related runtime dependencies.
- **Current State**:
  - Linux builds run from source in a configured GNUstep development environment.
  - No Flatpak manifest or CI pipeline currently publishes installable Linux bundles.
  - Runtime tools/features that depend on external binaries (for example `pandoc`) are not bundled for end users.
- **Requirements**:
  - Create a Flatpak manifest and builder flow for `MarkdownViewer`.
  - Include all required runtime components for app startup and core features (GNUstep libs, Objective-C runtime, cmark, OpenSave/TextViewVimKit dependencies, and other required shared libraries).
  - Include `pandoc` (or an equivalent clearly documented strategy) so import/export features work on stock systems.
  - Add GitHub Actions workflow(s) to build, validate, and publish Flatpak artifacts (nightly and/or tagged releases).
  - Validate installation and launch on a clean Linux box with no preinstalled GNUstep toolchain.
- **Notes**:
  - Target reproducible builds with pinned versions and explicit dependency provenance.

## 10) Tagged Linux AppImage release flow blocked by missing self-hosted GitHub runner

- **Status**: Open
- **Opened On**: 2026-04-14
- **Area**: Release engineering / GitHub Actions / Linux packaging
- **Description**: The tagged Linux AppImage workflow is intentionally configured to run on the self-hosted GNUstep runner label set `["self-hosted","linux","gnustep-clang"]`, but there are currently no registered runners in the repository, so the AppImage packaging job never starts.
- **Current State**:
  - `linux-appimage` resolves the package version successfully on tag push.
  - the reusable packaging job remains queued indefinitely on the self-hosted label set
  - `gh api repos/danjboyd/ObjcMarkdown/actions/runners` currently reports `total_count: 0`
- **Impact**:
  - blocks end-to-end confirmation that a release tag produces and publishes the Linux AppImage and `.zsync`
  - prevents `Phase 7B` / `Phase 8D` acceptance from going green for Linux
- **Next Step**:
  - register or restore the expected self-hosted GNUstep runner for this repository, or deliberately redesign the Linux packaging lane to run on a GitHub-hosted image with equivalent toolchain guarantees

## 11) Windows MSI rebuild handoff after WinUITheme/default-theme work

- **Status**: Open
- **Opened On**: 2026-04-14
- **Area**: Release engineering / Windows packaging / `gnustep-packager` integration
- **Description**: Repo-local packaging changes now require the Windows MSI to bundle `WinUITheme` and default to `WinUITheme`, but the ad hoc OCI remote rebuild path has not yet produced a fresh validated MSI carrying those changes.
- **Current State**:
  - `ObjcMarkdown` repo changes are in place to require `WinUITheme` in the staged payload and set `GSTheme=WinUITheme` with `policy: ifUnset` in [packaging/manifests/windows-msi.manifest.json](/home/danboyd/git/ObjcMarkdown/packaging/manifests/windows-msi.manifest.json).
  - Repo-local Windows theme input prep was updated to work with the managed MSYS2 `clang64` toolchain in [packaging/scripts/ensure-windows-theme-inputs.ps1](/home/danboyd/git/ObjcMarkdown/packaging/scripts/ensure-windows-theme-inputs.ps1).
  - Local Linux/dev launch regressions caused by the new updater libraries are fixed in [GNUmakefile](/home/danboyd/git/ObjcMarkdown/GNUmakefile) and [scripts/omd-viewer.sh](/home/danboyd/git/ObjcMarkdown/scripts/omd-viewer.sh).
  - An ad hoc remote Windows rebuild bundle exists on the OCI build VM under `C:\\Users\\otvmbootstrap\\omd-winremote`, but no fresh MSI has been copied back or pushed to the test VM yet.
- **External Findings**:
  - `gnustep-packager` implemented manifest-driven host dependency provisioning in commit `576a020`, including `hostDependencies.windows.msys2Packages` and reusable-workflow support.
  - `gnustep-packager` also fixed the Windows native-stderr warning handling issue.
  - Remaining best-practice upstream request is to strengthen declarative packaged content contracts / installed-package assertions so packaging correctness lives more fully in the packager boundary.
- **Last Known Remote Build Blocker**:
  - The remote Windows build reached the `ObjcMarkdown` compile and failed on missing `cmark.h`.
  - The immediate local fix was to update the ad hoc remote build script to install `mingw-w64-clang-x86_64-cmark` before invoking the packaging pipeline.
  - The long-term fix should be to declare `cmark` in the manifest under `hostDependencies.windows.msys2Packages` and then repin/use the updated `gnustep-packager` commit so host dependency realization happens systematically.
- **Phase 10A-C Recovery Findings (2026-04-30)**:
  - Connected to the known-good libvirt Windows VM at `172.17.2.148` as `Administrator`; hostname `OTVM-WIN-05SPHS`.
  - Captured environment and payload evidence in `dist/phase10-msi/` and summarized it in [docs/windows-phase10-msi-recovery.md](/home/danboyd/git/ObjcMarkdown/docs/windows-phase10-msi-recovery.md).
  - The known-good VM has `ObjcMarkdown` at `87ea70ed2df2bac8c634b6b82471339ce5dc8e6d` and `plugins-themes-WinUITheme` at `48d21f0a2ae97ca70a03197d93a305144635517f`.
  - The known-good runtime is not an existing `dist/packaging/windows/stage`; it is a source-tree app build using `C:\\Users\\Administrator\\AppData\\Local\\gnustep-cli`.
  - A temporary imported-payload stage produced an MSI through `gnustep-packager`; clean Windows install succeeded, then validation failed because the imported payload did not include TinyTeX.
  - The normal source stage includes TinyTeX but differs materially from the imported known-good payload, especially project DLL placement and overall runtime size.
  - Normal source staging on the gnustep-cli runtime still logs `/etc/profile` and `/c/...` path warnings, confirming a `gnustep-cli-new` mount-convention gap.
- **Phase 10D-G Recovery Work (2026-04-30)**:
  - [packaging/manifests/windows-msi.manifest.json](/home/danboyd/git/ObjcMarkdown/packaging/manifests/windows-msi.manifest.json) now declares `mingw-w64-clang-x86_64-cmark` under `hostDependencies.windows.msys2Packages`, declares required Windows theme inputs, sets packaged default theme `WinUITheme`, and ignores confirmed Windows system DLLs `DNSAPI.dll` and `IPHLPAPI.DLL` during MSI runtime closure checks.
  - [.github/workflows/windows-packaging.yml](/home/danboyd/git/ObjcMarkdown/.github/workflows/windows-packaging.yml) is repinned to `gnustep-packager` commit `4fc362a68b3e55191942c01a92cf2f8da82031bb`, which includes manifest-driven host dependency provisioning.
  - [scripts/windows/build-from-powershell.ps1](/home/danboyd/git/ObjcMarkdown/scripts/windows/build-from-powershell.ps1) and [packaging/scripts/ensure-windows-theme-inputs.ps1](/home/danboyd/git/ObjcMarkdown/packaging/scripts/ensure-windows-theme-inputs.ps1) now detect whether the managed MSYS runtime exposes Windows drives as `/c` or `/cygdrive/c` and only source `/etc/profile` when it exists.
  - The known-good VM validates the fixed build script against `C:\\Users\\Administrator\\AppData\\Local\\gnustep-cli`: `-Task command -Command pwd` resolves to `/cygdrive/c/Users/Administrator/git/ObjcMarkdown`, and `-Task stage -StageDir dist/phase10-source-stage-fixed/windows/stage` completes cleanly.
  - The temporary imported-payload MSI path is quarantined as evidence only under ignored `dist/phase10-msi/`; it is not a release path because it omits TinyTeX and imports the full mutable `gnustep-cli` runtime.
- **Manual MSI Validation Findings (2026-04-30)**:
  - Candidate `dist/packaging/windows/packages/phase10-manual/ObjcMarkdown-0.1.1-rc2-win64.msi` installed and launched on clean validation VM `lease-20260430203645-pbs16d` at `172.17.2.177`.
  - The installed payload includes `WinUITheme.dll` under `C:\\Users\\Administrator\\AppData\\Local\\ObjcMarkdown\\runtime\\lib\\GNUstep\\Themes\\WinUITheme.theme`, but the app launched with the GNUstep theme active.
  - Runtime inspection showed `GSTheme=WinUITheme` in the app defaults domain, while `NSGlobalDomain` had no `GSTheme`; app startup was still searching the old `clang64` packaged layout instead of the MSI's `runtime` layout for `defaults.exe` and bundled themes.
  - Local fix: [ObjcMarkdownViewer/main.m](/home/danboyd/git/ObjcMarkdown/ObjcMarkdownViewer/main.m) now searches `runtime\\bin\\defaults.exe` before `clang64\\bin\\defaults.exe` and checks `runtime\\lib\\GNUstep\\Themes` before the legacy packaged theme path.
  - Preferences validation found that clicking the `GNUstep Theme` popup opened the neighboring `Layout Mode` popup; Linux validation also showed broken hover tracking because Preferences used a custom popup overlay and manually drawn popup panel instead of native `NSPopUpButton` menu tracking.
  - Local fix: [ObjcMarkdownViewer/OMDAppDelegate.m](/home/danboyd/git/ObjcMarkdown/ObjcMarkdownViewer/OMDAppDelegate.m) now disables the custom Preferences popup overlay path so the theme and layout controls use native `NSPopUpButton` popup behavior.
- **Next Step**:
  - Rebuild the MSI through the normal source-built packaging path with the app-side runtime-layout and native-popup fixes.
  - Once a fresh MSI is produced, push the `.msi` and portable `.zip` to a clean Windows validation VM and re-run manual/UAT verification.

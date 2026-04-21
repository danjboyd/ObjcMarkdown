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
- **Description**: The tagged Linux AppImage workflow was intentionally configured to run on the self-hosted GNUstep runner label set `["self-hosted","linux","gnustep-clang"]`, but there were no registered runners in the repository, so the AppImage packaging job could not start.
- **Current State**:
  - `linux-appimage` has been moved back to the reusable `gnustep-packager` default hosted AppImage path.
  - The reusable workflow now owns hosted GNUstep toolchain bootstrap and smoke validation through `gnustep-cli-new`.
  - The ObjcMarkdown Linux preflight now prepares only app-specific packaging inputs, such as the Adwaita theme checkout.
- **Impact**:
  - no longer blocks job scheduling on missing self-hosted runners
  - still requires a fresh hosted AppImage packaging run before the GitHub release path can be considered validated
- **Next Step**:
  - run the normal `linux-appimage` workflow and classify any failure as an ObjcMarkdown build/stage issue, a packager issue, or a `gnustep-cli-new` bootstrap issue based on the uploaded diagnostics

## 10A) Adopt the `gnustep-cli-new` runner/toolchain contract in ObjcMarkdown packaging

- **Status**: Open
- **Opened On**: 2026-04-15
- **Area**: Release engineering / runner infrastructure / toolchain provisioning
- **Description**: The MSI/AppImage/GitHub runner process depends on having a reliable way to provision or validate the required GNUstep libraries and the correct clang-oriented toolchain flavor on disposable runners. `gnustep-packager` now uses `gnustep-cli-new` as the hosted runner bootstrap and smoke-validation path, so ObjcMarkdown needs to consume that contract instead of carrying ad hoc runner preparation.
- **Current State**:
  - `gnustep-packager` is the packaging boundary and owns the reusable MSI/AppImage workflows.
  - `gnustep-cli-new` now publishes the Linux and Windows artifacts consumed by the packager bootstrap path.
  - The ObjcMarkdown packaging workflows are pinned to the current packager integration commit and use the hosted default bootstrap path.
  - Repo-local build/stage scripts now prefer `GNUSTEP_MAKEFILES`, `GP_GNUSTEP_CLI_ROOT`, `MSYS2_LOCATION`, and the active managed clang64 prefix before falling back to legacy local paths.
- **Impact**:
  - blocks treating ObjcMarkdown as fully aligned with the current packager/CLI boundary until hosted packaging is rerun and the uploaded diagnostics are reviewed
  - any remaining failure should now be attributable to the app build/stage commands, the packager transform/validation layer, or the `gnustep-cli-new` bootstrap diagnostics rather than missing runner setup
- **Next Step**:
  - rerun hosted Linux AppImage and Windows MSI packaging through the normal reusable workflow path
  - review the uploaded `*-gnustep-cli-new`, logs, and validation artifacts for any remaining failures

## 11) Windows MSI rebuild handoff after WinUITheme/default-theme work

- **Status**: Open
- **Opened On**: 2026-04-14
- **Area**: Release engineering / Windows packaging / `gnustep-packager` integration
- **Description**: Repo-local packaging changes now require the Windows MSI to bundle `WinUITheme` and default to `WinUITheme`, but the ad hoc OCI remote rebuild path has not yet produced a fresh validated MSI carrying those changes.
- **Current State**:
  - `ObjcMarkdown` repo changes are in place to require `WinUITheme` in the staged payload and set `GSTheme=WinUITheme` with `policy: ifUnset` in [packaging/manifests/windows-msi.manifest.json](/home/danboyd/git/ObjcMarkdown/packaging/manifests/windows-msi.manifest.json).
  - Repo-local Windows theme input prep was updated to work with the managed MSYS2 `clang64` toolchain in [packaging/scripts/ensure-windows-theme-inputs.ps1](/home/danboyd/git/ObjcMarkdown/packaging/scripts/ensure-windows-theme-inputs.ps1).
  - Local Linux/dev launch regressions caused by the new updater libraries are fixed in [GNUmakefile](/home/danboyd/git/ObjcMarkdown/GNUmakefile) and [scripts/omd-viewer.sh](/home/danboyd/git/ObjcMarkdown/scripts/omd-viewer.sh).
  - The packaging workflows are now pinned to the current `gnustep-packager` integration commit and should use the normal reusable path instead of the ad hoc OCI remote rebuild bundle.
- **External Findings**:
  - `gnustep-packager` now provides manifest-driven host dependency provisioning, reusable dependency profiles such as `gnustep-cmark`, declarative packaged defaults, semantic package/install assertions, and the hosted `gnustep-cli-new` bootstrap gate.
  - `gnustep-cli-new` now publishes the Windows MSYS2 clang64 artifacts that the packager bootstrap path is expected to consume.
- **Next Step**:
  - Rebuild the MSI through the normal packaging path instead of the increasingly patched ad hoc OCI remote bundle.
  - Once a fresh MSI is produced, push the `.msi` and portable `.zip` to a Windows validation VM and re-run manual/UAT verification.

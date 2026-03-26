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

## 7) Automated Windows MSI packaging pipeline (GNUstep runtime included)

- **Status**: Open
- **Opened On**: 2026-02-19
- **Area**: Release engineering / Windows packaging / CI-CD
- **Description**: Build automated GitHub pipelines that produce a usable Windows MSI for the MSYS2/clang GNUstep build, including all required runtime components.
- **Current State**:
  - GitHub Actions `windows-packaging` workflow builds MSI on `windows-latest` using MSYS2 `clang64` + WiX.
  - Tagged artifact production is configured to build the MSI and portable ZIP in CI.
  - OCI golden-image validation is now the documented clean-machine path:
    - Runbook: `docs/windows-oci-msi-validation.md`
    - Guest-side installer validation: `scripts/windows/validate-msi.ps1`
    - OCI automation helpers:
      - `scripts/windows/oci-launch-validation-vm.ps1`
      - `scripts/windows/oci-open-rdp-rule.ps1`
      - `scripts/windows/oci-push-and-test-msi.ps1`
      - `scripts/windows/oci-terminate-validation-vm.ps1`
      - `scripts/windows/oci-run-msi-validation.ps1`
  - First full end-to-end OCI validation pass succeeded on `2026-03-26` against a locally built `0.1.0.0` MSI:
    - fresh OCI VM launched from the golden image,
    - MSI install succeeded,
    - smoke launch succeeded,
    - uninstall succeeded,
    - logs collected under `dist/oci-logs/20260326-132324`.
  - The main operational issue exposed by that pass was SSH reachability on a world-open port `22` rule:
    - the fresh Windows guest hit `Exceeded MaxStartups` until SSH ingress was temporarily narrowed to the current public IP,
    - the original broad `22` rule was restored after validation.
  - Fixed CI issues so far:
    - MSYS2 `mode_t` typedef clash avoided by forcing `-D__mode_t_defined -D_MODE_T_ -D_MODE_T_DEFINED`.
    - Skipped tests in Windows MSI build (`OMD_SKIP_TESTS=1`) because XCTest headers are not present.
    - Version resolution now tolerates missing tags.
- **Next Steps**:
  - Commit the current Windows/MSI/OCI scripts and doc updates so the OCI path is the repo-tracked source of truth.
  - Trigger or verify a tagged GitHub Actions run so MSI and portable ZIP artifacts are actually produced for the current workflow.
  - Encode the temporary SSH-ingress narrowing/restoration into the documented validation procedure or helper automation so repeat runs do not depend on manual intervention.
  - Run `scripts/windows/oci-run-msi-validation.ps1` against a CI-produced tagged artifact, not only a locally built MSI, and collect logs under `dist/oci-logs`.
  - If the automated pass fails, keep the disposable VM only long enough for targeted RDP/manual investigation, then terminate it.
  - Add a short manual visual follow-up after the automated pass for shortcut/icon/file-association checks if those remain part of the release gate.
- **Requirements**:
  - Generate MSI artifacts from GitHub Actions on tagged releases (and optionally on `main` as pre-release builds).
  - Bundle app binaries plus required runtime libraries (including GNUstep base/gui/back and dependent DLLs such as cmark, dispatch, OpenSave, TextViewVimKit, and Objective-C runtime dependencies).
  - Install/start menu shortcuts and uninstall entry should be included.
  - Validate clean-install launch on a fresh Windows environment (no preinstalled GNUstep/MSYS2).
- **Notes**:
  - Prefer reproducible packaging with explicit dependency manifests and versioned artifacts.

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

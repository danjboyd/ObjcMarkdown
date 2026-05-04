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

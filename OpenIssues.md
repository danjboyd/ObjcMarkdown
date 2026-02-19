# Open Issues

## 1) Open source license alignment (GNUstep)

- **Status**: Open
- **Area**: Project licensing
- **Description**: Choose license consistent with GNUstep (likely LGPL-2.1+ for libraries).
- **Notes**:
  - Evaluate GNUstep's recommended license.
  - Update `LICENSE` and source headers accordingly.

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

## 3) Phase-1 UI polish follow-up (post-regression cleanup)

- **Status**: Open
- **Opened On**: 2026-02-16
- **Area**: Viewer / Toolbar / Split UX
- **Description**: Finish final visual/interaction polish after Milestone 11 stabilization fixes.
- **Current State**:
  - Split-pane rendering regression is fixed.
  - Toolbar icon-loading regression is fixed.
- **Remaining Work**:
  - Verify zoom slider thumb/track visibility across GNUstep themes.
  - Finalize toolbar control vertical alignment without increasing toolbar height.
  - Decide whether `Preferences` should remain in the default toolbar set.
  - Optionally revisit preview background softening with a safer draw path.
- **Notes**:
  - Keep this scoped to visual/usability polish; avoid new behavior risk.
  - Capture before/after screenshots during each incremental tweak.

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

## 5) Sprint-1 editing correctness closeout

- **Status**: Open
- **Opened On**: 2026-02-17
- **Area**: Source editor UX / Formatting commands
- **Description**: Complete Sprint 1 hardening for deterministic editing behavior and test coverage.
- **Current State**:
  - `Enter` continuation/exit behavior is in place for list and quote structures.
  - List `Tab` / `Shift+Tab` indent-outdent behavior is implemented.
  - Inline wrap toggles were hardened for multiline/mixed selection behavior.
  - Added structured-newline regression tests for task-list, ordered-list increment, and blockquote exit paths.
- **Remaining Work**:
  - Add explicit tests for inline toggle reversibility on multiline/mixed selections.
  - Run a manual QA matrix for formatting commands in `Edit` and `Split` modes.
  - Triage and resolve any regressions discovered by that matrix.
- **Exit Criteria**:
  - Sprint 1 acceptance criteria in `Roadmap.md` are fully met and validated.

## 6) Inline HTML rendering support (deferred to Phase 2)

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

## 7) GFM table preview parity and narrow-pane behavior

- **Status**: Open
- **Opened On**: 2026-02-19
- **Area**: Renderer / GitHub parity / Preview layout
- **Description**: GitHub-flavored Markdown pipe tables do not currently render with GitHub-like structure/styling in preview, and table output degrades badly in narrow preview panes.
- **Current State**:
  - Recent renderer changes introduced table parsing and alternate layout paths.
  - In-app renderer now includes:
    - corrected table block row/column indexing for deterministic cell placement,
    - body-font table typography (no forced monospace table text),
    - improved narrow-width fallback heuristics based on visible cell text width (not raw markdown syntax length).
  - Remaining gap:
    - visual parity still needs side-by-side screenshot confirmation/tuning versus GitHub output.
  - A reproducible fixture exists in `TableRenderDemo.md`.
- **Repro**:
  1. Launch app with `gmake run TableRenderDemo.md`.
  2. Open in `Split` mode and compare preview against GitHub rendering.
  3. Shrink preview pane width and observe table distortion.
- **Next Work**:
  - Capture local-vs-GitHub screenshots for `TableRenderDemo.md` and evaluate each parity target in `GitHubTableParityChecklist.md`.
  - Tune header/body border + padding + line-height based on screenshot diffs.
  - Verify/readjust narrow-pane fallback threshold after visual comparison.
  - Keep renderer tests aligned with the finalized behavior.
- **Tracking**:
  - Use `GitHubTableParityChecklist.md` as the visual parity checklist for closure.

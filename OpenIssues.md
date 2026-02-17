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
- **Remaining Work**:
  - Add explicit tests for inline toggle reversibility on multiline/mixed selections.
  - Add explicit tests for list continuation edge cases (nested levels, task-list paths).
  - Run a manual QA matrix for formatting commands in `Edit` and `Split` modes.
  - Triage and resolve any regressions discovered by that matrix.
- **Exit Criteria**:
  - Sprint 1 acceptance criteria in `Roadmap.md` are fully met and validated.

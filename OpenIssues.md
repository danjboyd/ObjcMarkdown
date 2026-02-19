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

## 6) Default GNUstep theme compatibility pass

- **Status**: Open
- **Opened On**: 2026-02-19
- **Area**: Viewer / Theme compatibility / UAT
- **Description**: Validate and polish the app for the default GNUstep theme (separate from Sombre-focused polishing).
- **Current State**:
  - Recent visual/UAT work has been executed primarily against the Sombre theme.
- **Planned Work**:
  - Run core UX screens in default GNUstep theme (`Read`, `Edit`, `Split`, Preferences, alerts/dialogs).
  - Capture screenshots for default-theme baseline and log visual/usability deltas versus Sombre.
  - Fix theme-sensitive issues (contrast, control visibility, spacing/alignment, icon legibility) without regressing Sombre.
  - Re-run targeted UAT checklist after fixes.
- **Exit Criteria**:
  - Default-theme screenshots show no high-visibility control/readability regressions.
  - Core workflows are confirmed usable in both default GNUstep and Sombre themes.

# Open Issues

## 1) Hyperlinks do not open in default browser

- **Status**: Open
- **Area**: Viewer / Link interaction
- **Description**: Clicking hyperlinks in the rendered document does not open the default browser.
- **Repro**:
  1) `gmake run Resources/sample-commonmark.md`
  2) Click any link
  3) Nothing happens
- **Expected**: Default browser opens the link.
- **Actual**: No action.

## 2) Inline HTML handling

- **Status**: Open
- **Area**: Renderer / HTML
- **Description**: Inline HTML is currently not rendered. Consider parsing a safe subset in the future.
- **Repro**:
  1) `gmake run Resources/sample-commonmark.md`
  2) Inline HTML is rendered as plain text or ignored
- **Expected**: Either safe HTML subset rendering or explicit ignore.
- **Notes**: Evaluate Gumbo + minimal HTML→Markdown/attributes mapping.

## 3) Make library general‑purpose (reduce optional deps)

- **Status**: Open
- **Area**: Library architecture
- **Description**: Refactor so the core library has minimal dependencies (ideally only cmark). Move TOML/theme parsing to viewer or an extras target.
- **Notes**: Provide programmatic theme defaults; add compile flags for optional features.

## 4) Open source license alignment (GNUstep)

- **Status**: Open
- **Area**: Project licensing
- **Description**: Choose license consistent with GNUstep (likely LGPL‑2.1+ for libraries).
- **Notes**: Evaluate GNUstep’s recommended license; update LICENSE + headers accordingly.

## 5) Markdown parsing options API (NSAttributedStringMarkdownParsingOptions equivalent)

- **Status**: Open
- **Area**: Library API
- **Description**: Explore an API that mirrors Apple’s `NSAttributedStringMarkdownParsingOptions` for compatibility and configurability.
- **Notes**: Define a struct/class with options (flavor, base URL, inline HTML handling, etc.).

## 6) Feasibility: Pandoc Markdown embedded LaTeX support

- **Status**: Open
- **Opened On**: 2026-02-13
- **Area**: Renderer / Markdown flavor / Math
- **Description**: Evaluate whether to support Pandoc Markdown math syntax (`$...$`, `$$...$$`, and related forms) and how to render embedded LaTeX in the viewer.
- **Repro**:
  1) Open a Markdown file containing inline or block LaTeX math
  2) Observe output in viewer
- **Current Result**: Inline/display math is rendered as SVG attachments when TeX backend tools are available; otherwise it falls back to styled text.
- **Discussion Points**:
  - Decide whether the viewer should parse Pandoc-specific extensions in addition to CommonMark.
  - Decide rendering strategy (plain text fallback vs KaTeX/MathJax-style pipeline vs native equation rendering).
  - Define security and performance constraints for math rendering.
- **Initial Findings (2026-02-13)**:
  - Pandoc round-trip probe (`commonmark -> docx -> commonmark`) preserved math syntax text (`$...$` and `$$...$$`) in output.
  - Current gap is equation rendering in the viewer, not document conversion fidelity.
  - Prototype added in renderer: detect `$...$` and `$$...$$` spans in text nodes and style them as math-like spans.
  - Prototype intentionally does not do full LaTeX layout/typesetting yet (no TeX engine / MathJax/KaTeX equivalent in-process).
  - Implementation update: inline/display math now attempts TeX->DVI->SVG rendering (`tex` + `dvisvgm`) and embeds results as `NSTextAttachment`; fallback remains styled text when backend is unavailable or conversion fails.
  - Remaining work: harden caching/performance and define security constraints for untrusted TeX input.

## 7) SVG image embedding in rendered Markdown (NSTextAttachment path)

- **Status**: Open
- **Opened On**: 2026-02-13
- **Area**: Renderer / Inline media / Attachments
- **Description**: Add support for embedding SVG images in rendered Markdown content via `NSTextAttachment`.
- **Current Finding**:
  - GNUstep `NSAttributedString` attachments work for SVG on this machine through `GSImageMagickImageRep`.
  - Rendering path is bitmap-based after decode/rasterization, not retained vector drawing in text layout.
  - This path is now exercised by math rendering: LaTeX formulas are converted to SVG and embedded as attachments.
- **Implementation Recommendation**:
  1) Implement image node handling in renderer to create `NSTextAttachment` for local/remote image sources.
  2) Prefer loading via `NSImage` and normalize sizing against content width and DPI/zoom.
  3) Add a rasterization quality policy: generate at display scale (and optionally 2x) to reduce blur on zoom/print.
  4) Add graceful fallback text when image decode fails (`[image: alt]`) and surface errors in logs.
  5) Keep feature behind an option flag initially (`renderImages`), default on for viewer, off/optional for core library API.
- **Notes**:
  - Verify print/PDF export quality specifically for SVG attachments.
  - Re-evaluate true vector strategy later if quality/performance is insufficient.

## 8) Feasibility: Full WYSIWYG Markdown editor

- **Status**: Open
- **Opened On**: 2026-02-13
- **Area**: Viewer / Editor architecture / Markdown round-trip
- **Description**: Evaluate and plan implementation of a full WYSIWYG Markdown editor where visual edits reliably serialize back to Markdown without destructive rewrites.
- **Current State**:
  - Viewer text surface is read-only.
  - Rendering pipeline is one-way (`markdown -> NSAttributedString`), with no reverse mapping from attributed edits back to Markdown structure.
  - Save path persists `_currentMarkdown` source text, not an editable structured model.
- **Feasibility Assessment**:
  - Estimated difficulty: high (roughly 8/10).
  - Expected effort: multi-month for robust full-fidelity WYSIWYG; shorter for a hybrid editor.
- **Implementation Recommendation**:
  1) Build a hybrid editor first: editable Markdown source + synchronized styled preview pane.
  2) Introduce a document model layer (AST/blocks/inlines) decoupled from view rendering.
  3) Add incremental parse/render with cursor/selection stability and undo/redo integration.
  4) Implement Markdown serializer with round-trip guarantees and normalization rules.
  5) Ship constrained WYSIWYG subset first (headings, emphasis, lists, links, code blocks).
  6) Expand feature coverage (tables, images, math, HTML) only after round-trip test coverage is strong.
- **Notes**:
  - Recommendation is to avoid jumping directly to full WYSIWYG from current architecture.
  - Prioritize correctness and round-trip fidelity over immediate feature breadth.

## 9) Viewer-first editable source mode with live preview (Read/Edit/Split UX)

- **Status**: Open
- **Opened On**: 2026-02-13
- **Area**: Viewer / Editor UX / Rendering performance
- **Description**: Add a world-class, viewer-first editing model where users can toggle between read-only viewing and raw Markdown editing, with optional split preview for heavier editing workflows.
- **Product Direction**:
  - Default mode remains `Read` (viewer-first behavior).
  - `Edit` mode is optimized for quick source changes in a single pane.
  - `Split` mode is available for side-by-side source plus rendered preview.
- **Why this in addition to WYSIWYG**:
  - Lower complexity and faster delivery than full WYSIWYG.
  - Preserves markdown source fidelity and user control.
  - Matches current architecture (`markdown -> attributed render`) with incremental additions.
- **Implementation Path (recommended order)**:
  1) Introduce explicit view modes:
     - Add `Read | Edit | Split` state enum and toolbar/menu toggle actions.
     - Add keyboard shortcuts and visible mode indicator.
     - Preserve per-document mode and zoom preference.
  2) Add source editor surface:
     - Add editable raw Markdown text view with monospace font defaults.
     - Add dirty-state tracking and unsaved-change prompts.
     - Keep `Read` mode text view fully non-editable.
  3) Build live-preview pipeline:
     - In `Edit` and `Split`, render preview from editor buffer (not only saved file content).
     - Debounce preview updates only; do not debounce typing.
     - Cancel stale preview jobs and apply only the newest completed render.
  4) Preserve context across modes:
     - Maintain scroll/caret anchor when toggling modes.
     - Add source-to-preview and preview-to-source position mapping (best-effort first).
  5) Optimize heavy artifacts:
     - Keep existing async math generation and artifact-only debounce.
     - While high-res math is warming, show best available cached bitmap and swap in sharper result when ready.
     - Avoid blocking UI thread on TeX conversion.
  6) Add document lifecycle UX:
     - Autosave drafts and recovery for crash/restart.
     - Add explicit `Save` semantics from editor buffer back to markdown source.
     - Ensure import/export actions consume current in-memory source.
  7) Harden with tests and perf gates:
     - Unit tests for mode transitions and source-buffer rendering behavior.
     - Integration tests for edit->preview sync and dirty-state flows.
     - Perf target: typical edit-to-preview update under 100ms on sample docs; no visible stutter during slider or resize interaction.
- **Initial Milestone Recommendation (MVP)**:
  - Ship `Read` default + `Edit` toggle + debounced live preview in same window.
  - Add `Split` as second milestone after caret/scroll sync is stable.
- **Implementation Update (2026-02-13, end-of-day handoff)**:
  - Added `Read | Edit | Split` mode controls in toolbar and `View` menu (with `Cmd+1/2/3`).
  - Added raw Markdown source editor pane and split layout wiring.
  - Made split divider draggable and persisted divider ratio (`ObjcMarkdownSplitRatio`).
  - Added debounced live preview updates from source edits in `Split` mode.
  - Added source editor line numbers via ruler view.
  - Added source editor monospace font controls (`Choose Monospace Font`, `Increase`, `Decrease`, `Reset`) with persisted preferences.
  - Added source editor keyboard behavior so `Ctrl+Shift+Left/Right` performs word-wise selection (editor override).
  - Added font-panel action routing fix so chosen monospace font applies to the full source buffer immediately (not just new typing/selection).
  - Added mode persistence via `ObjcMarkdownViewerMode` user default and mode-aware window title/dirty marker.
- **Remaining Work (next session)**:
  1) Complete unsaved-change lifecycle:
     - Prompt on close/open/quit when source buffer is dirty.
     - Add explicit `Save` action semantics from in-memory buffer to disk path.
  2) Add source/preview position sync:
     - Best-effort scroll-anchor mapping between source and rendered preview.
     - Preserve caret/selection context more reliably when toggling modes.
  3) Continue performance hardening for large docs and math-heavy content:
     - Reduce expensive rerenders during rapid zoom/resize/edit bursts.
     - Improve math artifact cache/refresh policy around zoom changes.
  4) Add coverage and regression checks:
     - Tests for mode transitions, live preview flow, font controls, and editor keybindings.
  5) UX polish for viewer-first workflow:
     - Clear stale/refresh state indicator while preview is catching up.
     - Final pass on menu/shortcut consistency and discoverability.

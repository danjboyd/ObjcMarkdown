# GitHub Rendering Parity Checklist (Tables)

This checklist tracks visual/behavioral parity for GitHub-flavored Markdown pipe tables.

## Comparison Baseline

- Source fixture: `TableRenderDemo.md`
- GitHub reference: render the same fixture in a GitHub repo markdown preview
- Local app: `ObjcMarkdownViewer` in `Split` mode, preview zoom near 100-125%

## Parity Targets

1. Structure:
- Header row appears visually distinct from body rows.
- Cell boundaries are clearly readable.
- Column alignment (`left`, `center`, `right`) is preserved.

2. Styling:
- Border tone and header background are close to GitHub.
- Cell padding and row spacing are readable without looking oversized.
- Inline markdown inside cells remains rendered (links/emphasis/code).

3. Resizing behavior:
- In medium width, table remains structured and legible.
- In narrow width, renderer degrades gracefully (readable fallback), not distorted/collapsed output.

## Current Status (2026-02-19 EOD)

- Implemented/in progress:
- Parser-driven table handling path is in place.
- Test fixture and renderer test updates exist.
- Table block indexing/alignment path was tightened in renderer.
- Grid table typography now uses body-font defaults (instead of forced monospace) for GitHub-like readability.
- Narrow-pane fallback heuristics now use visible-cell text width estimation (not raw markdown syntax length), which reduces false fallback/distortion for link-heavy cells.

- Not yet matched:
- Full visual confirmation against GitHub screenshots is still pending.

## Next Iteration Plan

1. Capture before/after screenshots for `TableRenderDemo.md` in local preview and GitHub.
2. Tune colors/padding/line-height only where screenshot diffs still show visible parity gaps.
3. Re-check narrow-width behavior with screenshot evidence and adjust fallback threshold only if needed.
4. Mark each parity target as pass/fail with date-stamped notes.

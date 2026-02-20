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

## Current Status (2026-02-19 Late)

- Implemented/in progress:
- Parser-driven table handling path is in place.
- Rich table rendering now uses a custom attachment cell that draws parsed rows/cells directly in-view.
- Header fill, border tone, padding, and row spacing are tuned to match GitHub table styling.
- Grid typography now tracks body-font family/size (no forced monospace table text).
- Table attachments are now vector-drawn in-view (reduces blur compared with rasterized table images at zoom).
- Table geometry is snapped to pixel boundaries to improve sharpness at non-integer zoom levels.
- Viewer now allows horizontal overflow for wide tables (horizontal scrollbar) instead of dropping to stacked fallback.
- Renderer tests were updated for attachment-based table output and pass in current build.

- Closed:
- UAT comparison passed and Issue #7 is closed as of 2026-02-19.
- Decision on clickable links inside table cells remains optional follow-on scope for phase 1.

## Next Iteration Plan

1. If a mismatch is later reported, tune only targeted table constants (padding/line-height/colors).
2. Treat clickable table links as separate follow-on unless phase-1 scope changes.
3. Track any new table regressions as fresh issues rather than reopening the closed parity item.

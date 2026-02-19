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

- Not yet matched:
- Preview still diverges significantly from GitHub table appearance.
- Narrow preview widths can produce distorted output.

## Next Iteration Plan

1. Finalize deterministic table layout path for GNUstep that renders stable header/body/cell boundaries.
2. Tune colors/padding to approach GitHub visual baseline.
3. Keep/readjust narrow-width fallback so output remains readable.
4. Re-run fixture screenshots and update this checklist to pass/fail each target.

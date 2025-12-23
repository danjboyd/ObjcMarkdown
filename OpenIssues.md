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

## 3) Export to PDF (Viewer)

- **Status**: Open
- **Area**: Viewer
- **Description**: Add export-to-PDF functionality in the viewer.
- **Expected**: Render current document to a PDF file.
- **Notes**: Likely viewer-only feature; use a print/PDF context with the same layout.

## 4) Printing (Viewer)

- **Status**: Open
- **Area**: Viewer
- **Description**: Add printing support in the viewer.
- **Expected**: Print current document using standard print dialog.
- **Notes**: Likely viewer-only feature; reuse text layout without UI overlays.


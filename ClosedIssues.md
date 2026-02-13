# Closed Issues

## 1) Export to PDF (Viewer)

- **Status**: Closed
- **Closed On**: 2026-02-12
- **Area**: Viewer
- **Description**: Added export-to-PDF functionality in the viewer.
- **Resolution**:
  - Added `File -> Export as PDF...`.
  - Added `Export PDF` toolbar action.
  - Export uses a dedicated print/export text view and writes PDF via `NSPrintOperation` with fallback to `dataWithPDFInsideRect:`.

## 2) Printing (Viewer)

- **Status**: Closed
- **Closed On**: 2026-02-12
- **Area**: Viewer
- **Description**: Added printing support in the viewer.
- **Resolution**:
  - Added `File -> Print...` with standard `Cmd+P`.
  - Added `Print` toolbar action.
  - Printing uses a dedicated print/export text view to avoid UI overlays in output.

## 3) Multi-format import/export initiative (DOCX/ODT/RTF + Markdown-first flow)

- **Status**: Closed
- **Closed On**: 2026-02-13
- **Area**: Viewer / Import-Export / UX
- **Description**: Implemented multi-format import/export with a pandoc-only backend for MVP.
- **Resolution**:
  - Added converter abstraction (`OMDDocumentConverter`) and pandoc backend (`OMDPandocConverter`) with runtime detection.
  - Wired import for `.rtf`, `.docx`, and `.odt` to convert into Markdown using pandoc.
  - Wired export for `.rtf`, `.docx`, and `.odt` from current Markdown using pandoc.
  - Added install guidance alert when pandoc is unavailable.
  - Added smoke tests for extension handling and pandoc import/export command paths.

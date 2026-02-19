# File Associations

## Goal

Register `MarkdownViewer` as able to open:
- Markdown (`.md`, `.markdown`, `.mdown`)
- Rich Text (`.rtf`)
- Word OpenXML (`.docx`)
- OpenDocument Text (`.odt`)

## Current Status

### GNUstep on Linux (GNOME)

Implemented:
- Desktop entry MIME registration includes markdown + importable formats in `Resources/MarkdownViewer.desktop.in`.
- Installer refreshes desktop MIME cache in `scripts/install-desktop.sh`.
- Runtime file-open path auto-routes importable formats through converter in `ObjcMarkdownViewer/OMDAppDelegate.m`.

### GNUstep App Bundle Metadata

Implemented:
- `ObjcMarkdownViewer/MarkdownViewerInfo.plist` now declares:
  - `NSMIMETypes` for GNUstep metadata consumers.
  - `CFBundleDocumentTypes` for future macOS-compatible bundle metadata.

### macOS (future target)

Prepared:
- `CFBundleDocumentTypes` entries are already present in `ObjcMarkdownViewer/MarkdownViewerInfo.plist`.

Remaining when macOS build target is added:
- Verify LaunchServices registration during install.
- Validate Finder "Open With" behavior for all supported types.

### Windows/GNUstep (future target)

Remaining:
- Add installer-time registry registration for extensions and MIME types.
- Register a ProgID mapping to `MarkdownViewer.exe "%1"`.
- Validate shell double-click behavior and "Open with" entries.

## Notes

- File association should cover formats the app can open directly or import via converter.
- `docx`/`odt`/`rtf` opening depends on pandoc availability in runtime environment.

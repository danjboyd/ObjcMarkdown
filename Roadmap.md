# ObjcMarkdown Roadmap

## Current Position

`ObjcMarkdown` is in a `0.1` source-first preview phase.

The current priority is not to chase every Markdown-editor feature at once. The priority is to make the existing GNUstep/Linux path solid, understandable, and pleasant to use.

## Near-Term Work

- stabilize the source editor, preview renderer, and split-view sync on real documents
- continue UI/theme polish so the viewer feels at home on modern GNUstep desktops
- improve packaging and release engineering:
  - Linux CI on the required clang/libobjc2/libdispatch stack
  - Windows MSI validation
  - eventual Linux app packaging
- keep CommonMark behavior strong before going deeper on GitHub-flavored extensions

## Deferred Work

These are interesting, but they are not the current release gate:

- full WYSIWYG Markdown round-trip editing
- broad macOS release packaging
- large new feature areas that would dilute stabilization work

## Release Intent

- `0.1`: source build preview for GNUstep/Linux users
- next releases: stronger packaging, CI, and broader platform confidence without weakening the core editor/viewer path

## Internal Notes

Older milestone handoffs, validation notes, and working checklists now live under [docs/internal](docs/internal/README.md).

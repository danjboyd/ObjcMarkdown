# ObjcMarkdown

`ObjcMarkdown` is an Objective-C CommonMark renderer for GNUstep/macOS-style APIs, plus a small GNUstep desktop app named `MarkdownViewer` for reading, editing, and previewing Markdown.

## Status

This repository is currently a `0.1` source-first preview.

- Primary supported environment: GNUstep on Linux with a clang/libobjc2/libdispatch toolchain.
- Windows support exists, but it is still experimental. See [WINDOWS_BUILD.md](WINDOWS_BUILD.md).
- macOS compatibility is still a project goal, but there is not yet a maintained macOS setup guide in this repo.

## What Is Here

- `ObjcMarkdown/`: library code that converts CommonMark Markdown into `NSAttributedString`
- `ObjcMarkdownViewer/`: `MarkdownViewer`, a minimal GNUstep Markdown viewer/editor
- `Resources/`: bundled themes, icons, and sample documents

Current viewer capabilities include:

- `Read`, `Edit`, and `Split` modes
- linked source/preview scrolling in split view
- syntax highlighting and an optional formatting bar
- theme-aware UI with GNUstep theme and layout-mode preferences
- local file explorer and GitHub browsing helpers
- optional import/export flows through external tools such as `pandoc` when available

## Markdown Support

The renderer is centered on CommonMark, with a few pragmatic viewer/editor additions on top.

Currently supported in the preview path:

- CommonMark headings, paragraphs, emphasis, strong emphasis, inline code, and fenced or indented code blocks
- blockquotes, ordered lists, unordered lists, and thematic breaks
- links, relative links with base-URL resolution, and image attachments with fallback text when decoding fails
- inline and block HTML as safe fallback text by default, with an explicit ignore policy available in code
- optional math styling for inline and display math
- GitHub-style pipe tables in preview, including horizontal overflow for wide tables
- optional renderer syntax highlighting for code blocks when the required tooling is available

Editor-side conveniences include:

- formatting-bar commands for headings, inline formatting, links, images, lists, code blocks, tables, and rules
- structured newline handling for lists, task lists, ordered lists, and blockquotes
- split-view source/preview synchronization

## Document Import And Export

Native/document-first behavior:

- open and edit Markdown files directly
- export the rendered document to PDF from the viewer

Pandoc-backed conversions, when `pandoc` is installed:

- import: `RTF`, `DOCX`, `ODT`, `HTML`, `HTM`
- export: `RTF`, `DOCX`, `ODT`, `HTML`, `HTM`

If `pandoc` is unavailable, those non-Markdown import/export formats are disabled, but PDF export from the viewer remains available.

## Screenshots

### Read mode

![MarkdownViewer read mode](docs/screenshots/read-mode.png)

### Split mode

![MarkdownViewer split mode](docs/screenshots/split-mode.png)

### Preferences

![MarkdownViewer preferences window](docs/screenshots/preferences.png)

### Edit mode

![MarkdownViewer edit mode](docs/screenshots/edit-mode.png)

## Toolchain Requirements

This project is validated against a clang-based GNUstep stack with `libobjc2` and `libdispatch`.

Important: stock Debian/Ubuntu GNUstep packages are commonly built around the GCC Objective-C runtime and are not a drop-in environment for this repo. The supported path is a clang/libobjc2/libdispatch GNUstep installation, either from your own packages or from a source build using GNUstep's tooling.

If you are building GNUstep yourself on Debian-like systems, the reference path on this machine is GNUstep's clang flow from `tools-scripts`. See [docs/linux-clang-toolchain.md](docs/linux-clang-toolchain.md).

## Build On GNUstep/Linux

1. Clone the repo and submodules:

```bash
git clone https://github.com/danjboyd/ObjcMarkdown.git
cd ObjcMarkdown
git submodule update --init --recursive
```

2. Source the GNUstep environment:

```bash
source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh
```

3. Build:

```bash
gmake
```

4. Run the app:

```bash
gmake run Resources/sample-commonmark.md
```

Notes:

- `cmark` headers and libraries must be available to the toolchain.
- `third_party/libs-OpenSave` and `third_party/TextViewVimKit` are required submodules.
- The GNUstep build on the authoring machine currently uses GNUstep Base `1.31.1`.

## Run Tests

The test runner is `tools-xctest`.

```bash
scripts/ci/run-linux-ci.sh
```

That script builds the repo, prepares the GNUstep defaults lock directory, and runs:

```bash
xctest ObjcMarkdownTests/ObjcMarkdownTests.bundle
```

## CI

GitHub Actions includes a Linux build/test workflow for the GNUstep clang environment used by this project. That lane intentionally targets a self-hosted runner with the required `clang`/`libobjc2`/`libdispatch` GNUstep stack instead of pretending stock distro GNUstep packages are sufficient.

The current Linux CI entry point is:

- [linux-gnustep-clang.yml](.github/workflows/linux-gnustep-clang.yml)

## Public Docs

- [Roadmap.md](Roadmap.md)
- [OpenIssues.md](OpenIssues.md)
- [ClosedIssues.md](ClosedIssues.md)
- [WINDOWS_BUILD.md](WINDOWS_BUILD.md)
- [docs/linux-clang-toolchain.md](docs/linux-clang-toolchain.md)

Working notes, milestone handoffs, and validation checklists that were cluttering the repo root now live under [docs/internal](docs/internal/README.md).

## License

Licensing is split by component:

- `ObjcMarkdown/`: `LGPL-2.1-or-later`
- `ObjcMarkdownViewer/` and `ObjcMarkdownTests/`: `GPL-2.0-or-later`
- `third_party/`: upstream licenses apply

See [LICENSE](LICENSE) and [LICENSES/](LICENSES).

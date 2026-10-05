## Project
Objective-C library (GNUstep + macOS compatible) that converts CommonMark Markdown
to `NSAttributedString`, plus a minimal viewer app.

## Goals
- Target CommonMark first, then add GitHub-flavored extensions.
- Provide a default GitHub-like theme with TOML configuration.
- Keep the MVP API simple; leave hooks for customization later.

## Build (GNUstep / Linux)
Prereqs:
- GNUstep installed and available at `/usr/GNUstep`.
- `gmake` and a C/ObjC toolchain.

Steps:
1) `source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh`
2) `gmake`
3) Run app: `gmake run` or `gmake run AGENTS.md` to open a file directly

Notes:
- GNUstep Base version on this box (from `GSConfig.h`): 1.31.1.

## Tests (GNUstep / Linux)
Framework:
- `tools-xctest` (installed). Source checkout at `../gnustep/tools-xctest`.

Workflow:
1) Source GNUstep environment: `source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh`
2) Build: `gmake`
3) Ensure lock dir exists: `mkdir -p ~/GNUstep/Defaults/.lck`
4) Run tests: `LD_LIBRARY_PATH=$PWD/ObjcMarkdown/obj:/usr/GNUstep/System/Library/Libraries xctest ObjcMarkdownTests/ObjcMarkdownTests.bundle`

## Process
- Before asking the user to run the app, the agent should build and get tests green.
- To check the app by eye without touching the desktop, use the private GNOME display scripts in `tools/dev/` (see `tools/dev/README.md`). The latest session handoff is `docs/internal/handoff-2026-10-05.md`.
- Track bugs in `OpenIssues.md`. When resolved, move them to `ClosedIssues.md`.
- Use git commit author `Daniel Boyd <danieljboyd@icloud.com>` for all commits in this repo.
- Use the GitHub account `danjboyd` for commits, pushes, PRs, releases, and other GitHub-authenticated operations for this repo.
- If `gh auth status` shows a different active account, switch with `gh auth switch -u danjboyd` before doing GitHub-authenticated work.
- Going forward, use `OracleTestVMs` configured for libvirt-backed leases as the default VM path for Debian and Windows UAT/validation unless the user explicitly asks for a different backend.
- Windows MSI release requirements:
  - bundle `WinUITheme` with the installed runtime payload
  - set `WinUITheme` as the default packaged Windows theme unless the user explicitly changes it

## Build (macOS)
TBD: add separate build instructions when macOS target is set up.

## Dependencies
- `cmark-gfm` (vendored in `third_party/cmark-gfm`, compiled into the library) for CommonMark + GFM parsing. Parse through `OMGFMParseDocument()` (`ObjcMarkdown/OMGFMParser.h`) so the renderer, split sync and source highlighter agree on block structure; never link a system `libcmark` alongside it.
- `tomlc99` (vendored in `third_party/tomlc99`) for theme TOML parsing.

## Structure (expected)
- `ObjcMarkdown/` library sources
  - The renderer is split by topic: `OMMarkdownRenderer.m` (the class, block and inline rendering, final passes), `OMMarkdownRendererSource.m` (rendered objects, block anchors, source lines), `OMMarkdownRendererCode.m` (syntax highlighting), `OMMarkdownRendererImages.m`, `OMMarkdownRendererMath.m`, `OMMarkdownRendererTables.m` and `OMMarkdownRendererMermaid.m`. Helpers shared between them are declared in `OMMarkdownRendererInternal.h` (not installed; hidden visibility); everything else stays `static`.
- `ObjcMarkdownViewer/` app sources
- `Resources/` theme TOML and assets

## Conventions
- Keep code ASCII by default.
- Prefer small, readable Objective-C units with minimal magic.

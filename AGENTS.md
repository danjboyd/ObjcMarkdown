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
- `cmark` library + headers (CommonMark reference implementation; `cmark.h` must be on include path).

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
- Track bugs in `OpenIssues.md`. When resolved, move them to `ClosedIssues.md`.

## Build (macOS)
TBD: add separate build instructions when macOS target is set up.

## Dependencies
- `cmark` for CommonMark parsing.
- `tomlc99` (vendored in `third_party/tomlc99`) for theme TOML parsing.

## Structure (expected)
- `ObjcMarkdown/` library sources
- `ObjcMarkdownViewer/` app sources
- `Resources/` theme TOML and assets

## Conventions
- Keep code ASCII by default.
- Prefer small, readable Objective-C units with minimal magic.

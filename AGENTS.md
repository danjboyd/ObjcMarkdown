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

## UI design principle
The app is the app; the theme and the user's theme settings decide whether it looks like GNOME, GNUstep, Windows or anything else. Follow this in every UI change:
1. Standard controls only: NSButton, NSSegmentedControl, NSPopUpButton, NSColorWell, NSSlider, NSSwitch, NSTextField, plain NSToolbarItems with images, so each theme draws them. No custom views that paint chrome (backgrounds, borders, pills, cards, rounded plates, "active" states). A custom `drawRect:` is fine for the document itself (the rendered preview, a diagram, an image), not for chrome.
2. System colours only for chrome: `windowBackgroundColor`, `controlBackgroundColor`, `textBackgroundColor`, `controlShadowColor` (lines, borders), `labelColor`/`secondaryLabelColor`/`controlTextColor`, `selectedControlColor`/`keyboardFocusIndicatorColor`, `toolTipColor`/`toolTipTextColor` (transient notices). Never hard-code, blend or pick an accent.
3. No app-level light/dark setting, no light and dark icon sets, no recolouring icons in the app. Light or dark is the theme's and the desktop's choice. Two settings are allowed in Preferences: the GNUstep theme (it writes the global `GSTheme` default, the same one GNUstep's own preferences use, and takes effect on the next launch) and the layout density (spacing and sizes only). They choose which theme draws the app and how roomy it is; neither may make the app paint itself to imitate a theme.
4. One monochrome ("symbolic") icon set, named `<name>-symbolic` (or `...Template`) so themes that tint template images find them; when loading from a file, `-setName:` the image with that name. The app's set is in `Resources/icons`, made by `tools/icons/make-symbolic-icons.py`; load it with `OMDSymbolicImageNamed()`. (The Adwaita theme tints them in buttons, toolbar items, menus and segmented controls.)
5. Declare intent and let the theme present it: `-setTitleWithRepresentedFilename:`, a toolbar with a flexible space between start and end items, Info.plist declarations a theme may read (`GnomeThemeHeaderBarToolbar`). Don't declare what is the user's choice (menu bar vs primary menu: `GnomeThemeMenuStyle`).
6. No theme detection: don't branch on a theme's name, and don't add settings that only make sense for one theme (the theme chooser in rule 3 lists whatever themes are installed). If something truly can't be expressed otherwise, keep it to one small check of a capability, not a name, and file the gap with the theme or GNUstep.
7. Keep the app usable and native-looking under both GNUstep's default theme and Adwaita, and check UI changes under both.

GNUstep notes for this:
- Images drawn with `-lockFocus` are window-cached reps and may composite blank; `graphicsContextWithBitmapImageRep:` can stay empty. Prefer a standard control, or write pixels directly.
- Image-only buttons: don't use rounded/textured bezels, whose padding can squeeze the image to nothing; use plain toolbar items or borderless buttons.
- NSPopover isn't usable in GNUstep 0.32; a custom popover panel may be an unavoidable exception, drawn in system colours.
- Custom views in toolbars must handle `-mouseDown:` themselves (or be real NSControls), or a header bar may take the press for a window drag.
- Instant-apply preferences: no Close/OK buttons (the window's close button closes); confirm destructive actions such as Restore Defaults.
- Tests and UI checks must not touch the user's settings or running apps: GNUstep ignores `$HOME` for defaults, so `tools/dev/` points `GNUSTEP_CONFIG_FILE` at a private copy of `/etc/GNUstep/GNUstep.conf` (mode 600) with its own defaults directory, and only ever stops the MarkdownViewer it started. Never stop the app by name (`pkill -x MarkdownViewer`).

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

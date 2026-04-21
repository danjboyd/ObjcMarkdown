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

## 4) Hyperlinks do not open in default browser

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Viewer / Link interaction
- **Description**: Clicking hyperlinks in rendered documents was unreliable/silent when open failed.
- **Resolution**:
  - Kept delegate-based link handling in preview text view.
  - Added `textView:clickedOnLink:atIndex:` forwarding support for broader NSTextView delegate compatibility.
  - Hardened open flow to check `NSWorkspace openURL:` result and use `xdg-open` fallback on GNUstep/Linux.
  - Added user-visible failure feedback (`NSBeep`) when link open fails.

## 5) Inline HTML handling

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Renderer / HTML
- **Description**: Inline/block HTML content was being dropped.
- **Resolution**:
  - Added explicit HTML handling in renderer for block and inline HTML nodes.
  - Default behavior now renders HTML as literal text instead of dropping nodes.
  - Added configurable HTML policies via parsing options (`RenderAsText` vs `Ignore`).
  - Added renderer tests covering inline HTML and block HTML behavior.

## 6) Make library general-purpose (reduce optional deps)

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Library architecture
- **Description**: Core library should support reduced optional dependencies.
- **Resolution**:
  - Added compile-time feature gate for TOML theme parsing: `OBJCMARKDOWN_ENABLE_TOML_THEME`.
  - Core library now builds with or without `tomlc99` source integration.
  - `OMTheme` cleanly falls back when TOML support is disabled.

## 7) Markdown parsing options API (NSAttributedStringMarkdownParsingOptions equivalent)

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Library API
- **Description**: Provide configurable parsing/render options compatible with future extensibility.
- **Resolution**:
  - Added `OMMarkdownParsingOptions` API.
  - Added renderer initializer accepting options: `initWithTheme:parsingOptions:`.
  - Added options for cmark flags, base URL, HTML policy, image policy, remote image policy, and math rendering policy.
  - Viewer now sets document base URL for relative link/image resolution.
  - Added tests for math-disabled policy, HTML ignore policy, and base-URL link resolution.

## 8) SVG image embedding in rendered Markdown (NSTextAttachment path)

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Renderer / Inline media / Attachments
- **Description**: Renderer lacked practical image-node attachment support.
- **Resolution**:
  - Implemented `CMARK_NODE_IMAGE` attachment rendering through `NSImage` + `NSTextAttachment`.
  - Added layout-width-aware image sizing for preview readability.
  - Added descriptive fallback text (`[image: alt]`) when image decoding fails.
  - Added test coverage for image attachment/fallback behavior.

## 9) Source editor font chooser emits error beep on apply

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Viewer / Source editor UX
- **Description**: Applying a font from the source editor font panel produced an error beep and failed to apply in some environments.
- **Resolution**:
  - Removed hard-fail beep path in `changeFont:`.
  - Font selection now always flows through `setSourceEditorFont:persistPreference:` which already enforces monospace fallback safely.
  - This preserves editor monospace behavior without noisy false-negative beeps.

## 10) Dirty-close alert buttons beep on "Don't Save" / "Cancel"

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Viewer / Window close flow
- **Description**: Unsaved-changes confirmation produced an error beep when handling non-primary buttons under GNUstep.
- **Resolution**:
  - Added alert response normalization for both legacy and modern AppKit-style return codes.
  - Updated discard-confirmation flow to branch on normalized button index.
  - Added a small `NSWindow` subclass override for `performClose:` to avoid GNUstep's refusal-beep path when canceling a close.
  - "Don't Save" and "Cancel" now map correctly without error-beep behavior from mismatched response constants or close-refusal beeps.

## 11) Viewer math policy controls not discoverable

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Viewer / Math UX
- **Description**: Math rendering policy and remote image policy existed in code/defaults but lacked direct UI control.
- **Resolution**:
  - Added `View -> Math Rendering` submenu with:
    - `Styled Text (Safe)`
    - `Disabled (Literal $...$)`
    - `External Tools (LaTeX)`
  - Added `Allow Remote Images` toggle in the same submenu.
  - Added menu checkmark state wiring and persisted preferences through existing defaults keys.
  - Triggered immediate preview rerender after policy changes.

## 12) Missing autosave/recovery for dirty source buffers

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Viewer / Editor resilience
- **Description**: Dirty buffers could be lost without recovery support after interruption/crash.
- **Resolution**:
  - Added debounced autosave snapshot writes for dirty source edits.
  - Added startup recovery prompt (`Recover` / `Discard`) when a snapshot exists.
  - Recovery restores markdown content and source path context when available.
  - Recovery snapshot is cleared on explicit save and normal close paths.

## 13) Remote image toggle did not hide already-rendered remote images

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Renderer / Images / Policy enforcement
- **Description**: Turning `Allow Remote Images` off left previously rendered remote attachments visible.
- **Resolution**:
  - Updated image attachment cache keying to include remote-image policy state.
  - Policy changes now force fresh attachment resolution so disabling remote images reverts to fallback text on rerender.

## 14) Ctrl+Shift+Arrow word selection inconsistent in source editor

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Viewer / Source editor input behavior
- **Description**: In source editor, `Ctrl+Shift+Left/Right` could select a single character instead of word segments.
- **Resolution**:
  - Added explicit source-editor key handling for `Ctrl+Shift+Left/Right`.
  - Implemented deterministic word-boundary selection logic for both directions.
  - Added command-dispatch interception in `OMDSourceTextView doCommandBySelector:` so behavior remains correct even when GNUstep key translation bypasses raw key checks.
  - Kept behavior local to `OMDSourceTextView` to avoid app-wide side effects.

## 15) Image attachment line clipping with fixed paragraph line height

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Renderer / Typography / Inline media
- **Description**: Inline image attachments could visually clip/overlap adjacent text when paragraph styles forced fixed maximum line heights.
- **Resolution**:
  - Removed hard `maximumLineHeight` clamp from shared paragraph-style helper.
  - Paragraphs now keep minimum line-height guidance while allowing taller inline attachments to expand line fragments safely.

## 16) Source-editor word-selection shim needed user-level control

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Viewer / Input behavior / Preferences
- **Description**: The Ctrl/Cmd+Shift+Arrow word-selection compatibility shim should be configurable for users with custom keybinding expectations.
- **Resolution**:
  - Added persisted preference key: `ObjcMarkdownWordSelectionShimEnabled`.
  - Default behavior remains enabled for compatibility.
  - Added `View` menu toggle: `Word Selection for Ctrl/Cmd+Shift+Arrow`.

## 17) Missing central place for runtime editor/viewer preferences

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Viewer / UX / Configuration
- **Description**: Growing runtime options (math policy, remote images, input behavior) needed a dedicated settings surface.
- **Resolution**:
  - Added `Preferences...` entry (`Cmd+,`) in the app menu.
  - Added lightweight Preferences panel with controls for:
    - Math rendering policy
    - Allow remote images
    - Source-editor word-selection shim
  - Preferences stay synchronized with existing View-menu quick toggles.

## 18) Duplicate block-ID anchor mapping ambiguity in stale-preview sync

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Viewer / Preview sync / Stale-render mapping
- **Description**: When repeated blocks produced identical stable block IDs, stale-preview mapping could pick the wrong repeated block.
- **Resolution**:
  - Added occurrence-order disambiguation between source descriptors and renderer anchors for identical block IDs.
  - Source->target and target->source block-ID mapping now prefer matching ordinal occurrence before falling back to proximity scoring.
  - Added regression tests for duplicate-block mapping in both directions and invalid zero-length anchor fallback.

## 19) Phase-1 source-editor syntax highlighting

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Viewer / Source editor UX
- **Description**: Added first-pass Markdown syntax highlighting to improve editing readability without blocking typing stability.
- **Resolution**:
  - Implemented `OMDSourceHighlighter` with a lightweight line/regex pass for:
    - headings, blockquotes, lists, links, emphasis, inline/fenced code, and math spans.
  - Added persisted runtime toggle:
    - `View -> Source Syntax Highlighting`
    - `Preferences... -> Source Syntax Highlighting`
  - Added highlighter tests, including a large-document performance guardrail.

## 20) Source syntax-highlighting toggle caused split-preview instability

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Viewer / Split mode / Source highlighting
- **Description**: Disabling source syntax highlighting could trigger unintended source-change flows and destabilize split preview behavior.
- **Resolution**:
  - Added a dedicated programmatic-highlighting guard flag so style-only updates do not enter markdown text-change paths.
  - Updated highlight-disable path to remove foreground attributes without recursive text-change side effects.
  - Ensured source-highlight refresh no-ops cleanly when highlighting is disabled.

## 21) Renderer code-block syntax highlighting (Objective-C phase 1)

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Renderer / Code blocks / Read experience
- **Description**: Preview code blocks rendered as uniformly styled text with no syntax token differentiation.
- **Resolution**:
  - Added first-pass fenced code-block syntax highlighting for Objective-C/C-family fences in the renderer.
  - Implemented token coloring for keywords, directives, strings, comments, and numeric literals.
  - Added renderer test coverage to confirm distinct token colors in Objective-C fenced blocks.

## 22) Renderer syntax-highlighting preference + Tree-sitter availability gating

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Viewer / Preferences / Renderer policy
- **Description**: Renderer syntax highlighting needed user-level control and explicit dependency UX when Tree-sitter is unavailable.
- **Resolution**:
  - Added persisted renderer toggle:
    - `View -> Renderer Syntax Highlighting`
    - `Preferences... -> Renderer Syntax Highlighting (Code Blocks)`
  - Added parsing option flag: `codeSyntaxHighlightingEnabled`.
  - Gated renderer highlighting on Tree-sitter runtime availability.
  - Preferences panel now disables renderer toggle and shows dependency guidance when Tree-sitter is missing.

## 23) Phase-1 source highlighting hardening (parser-backed + incremental + accessibility)

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Viewer / Source editor UX / Performance
- **Description**: Complete phase-1 hardening for source highlighting fidelity, performance behavior on large files, and accessibility controls.
- **Resolution**:
  - Added parser-backed block-style classification (via cmark source positions) for headings, blockquotes, lists, and code blocks.
  - Added incremental target-range highlighting support for large documents with adaptive debounce and full-pass fallback on structural changes.
  - Added source-highlight accessibility controls:
    - `View -> Source Highlight High Contrast`
    - `Preferences... -> High Contrast Source Highlighting`
    - `Preferences... -> Source Accent Color` (+ reset)
  - Added test coverage for parser-backed indented code styling, option overrides, and target-range incremental behavior.

## 24) Renderer fenced-code language coverage expansion (phase 1)

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Renderer / Code blocks / Language coverage
- **Description**: Extend fenced-code highlighting beyond initial Objective-C/C-family baseline.
- **Resolution**:
  - Expanded fence token language mapping to additional ecosystems:
    - Java/Kotlin/Swift/Go/Rust/C#/PHP (C-family baseline tokenization)
    - YAML, TOML, SQL, Ruby, HTML/XML/CSS
  - Added language-specific tokenization passes for YAML/TOML/SQL/Ruby/markup.
  - Added regression tests for SQL and YAML fenced blocks.

## 25) Mode-transition and preview-state coverage/discoverability hardening

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Viewer / Read-Edit-Split UX
- **Description**: Improve mode-transition state coverage and make preview sync state more discoverable.
- **Resolution**:
  - Added a shared mode-state module (`OMDViewerModeState`) for pane visibility and preview-status derivation.
  - Integrated toolbar preview status indicator (`Preview: live/updating/stale/hidden`) next to mode controls.
  - Added deterministic tests for mode pane-state and preview-status state transitions.

## 26) Math policy transition + stress guardrail coverage (phase 1)

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Renderer / Math policies / Performance testing
- **Description**: Expand math policy transition and stress-test coverage for phase-1 math hardening.
- **Resolution**:
  - Added policy transition test: styled -> disabled -> styled behavior is stable and reversible.
  - Added math-heavy styled-text render performance guardrail test.

## 27) Split-pane rendering corruption after UI polish background tweak

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Viewer / Split mode / Visual stability
- **Description**: A preview background softening tweak introduced split-pane rendering artifacts/clipping.
- **Resolution**:
  - Removed the risky app-level preview background override.
  - Restored renderer-driven preview background handling.
  - Revalidated split-mode rendering behavior after rollback.

## 28) Toolbar icon regression for primary actions (`Open` / `Save`)

- **Status**: Closed
- **Closed On**: 2026-02-16
- **Area**: Viewer / Toolbar / Resource loading
- **Description**: Primary toolbar icons stopped rendering consistently in GNUstep.
- **Resolution**:
  - Added robust toolbar-image loading with explicit bundle-path fallback.
  - Updated toolbar item construction to use fallback-aware image lookup.
  - User verification confirmed `Open`/`Save` icon rendering issue is resolved.

## 29) Source editor line-number gutter click artifacts

- **Status**: Closed
- **Closed On**: 2026-02-18
- **Area**: Viewer / Source editor / Line-number ruler
- **Description**: Clicking in the source-editor line-number gutter could produce visual artifacts along the left edge.
- **Resolution**:
  - Made line-number ruler mouse interactions inert by consuming gutter mouse events (`mouseDown`, drag/up, and alternate-button down).
  - Prevented default `NSRulerView` interaction paths from running on gutter clicks.

## 30) Source-editor selection highlight too bright and syntax-obscuring

- **Status**: Closed
- **Closed On**: 2026-02-18
- **Area**: Viewer / Source editor / Selection styling
- **Description**: Source selection highlight was overly bright under some GNUstep themes and could obscure syntax-color distinctions.
- **Resolution**:
  - Added source-editor-specific selected-text styling with a calmer semi-transparent blue background tuned against editor background luminance.
  - Set source-editor selected-text attributes to use a custom calm background and transparent selected-foreground override.
  - Added selected-range syntax overlay drawing in `OMDSourceTextView` so selected text re-renders with original token foreground colors.
  - Added regression test coverage for selection-style defaults and non-mutation of stored syntax foreground attributes.

## 31) Source editor hover cursor showed arrow instead of text insertion cursor

- **Status**: Closed
- **Closed On**: 2026-02-18
- **Area**: Viewer / Source editor / Cursor UX
- **Description**: Hovering source-editor text could show the default arrow cursor rather than an insertion (I-beam) cursor.
- **Resolution**:
  - Added explicit source-editor cursor rect handling in `OMDSourceTextView resetCursorRects`.
  - Source editor now forces `IBeamCursor` over visible editing content with arrow fallback only if unavailable.

## 32) I-beam cursor leaked into modal save-confirmation dialog

- **Status**: Closed
- **Closed On**: 2026-02-18
- **Area**: Viewer / Source editor / Cursor UX
- **Description**: After Vim `:q` on dirty documents, cursor forcing from source editor could persist as I-beam while hovering the save-confirmation dialog where arrow cursor is expected.
- **Resolution**:
  - Scoped source-editor cursor forcing to only run when the source view is first responder, in the key window, and currently hovered.
  - Added modal-window guard so deferred cursor updates do not override cursor shape while alert dialogs are active.
  - Switched deferred cursor update to a view-scoped callback (`omdApplyDeferredEditorCursorShape`) with condition re-checking before applying I-beam.
  - Before dirty-close confirmation `runModal`, now cancels pending source-view deferred cursor updates and explicitly sets arrow cursor.
  - Disabled selectable `NSTextField` behavior in the close-confirmation alert window so GNUstep alert text regions also keep arrow cursor.

## 33) Link opening lacked explicit safe scheme allowlist

- **Status**: Closed
- **Closed On**: 2026-02-18
- **Area**: Viewer / Link safety / Navigation policy
- **Description**: Link rendering/opening accepted arbitrary URL schemes, risking unsafe or surprising launches from Markdown content.
- **Resolution**:
  - Added explicit link scheme allowlist in renderer and viewer open path (`file`, `http`, `https`, `mailto`).
  - Disallowed schemes now do not get `NSLink` attributes and are blocked from runtime open attempts.
  - Added renderer tests for blocked `javascript:` links and allowed `mailto:` links.

## 34) Remote image fetch could block render path

- **Status**: Closed
- **Closed On**: 2026-02-18
- **Area**: Renderer / Performance / Remote image policy
- **Description**: Remote image fetches in render path used synchronous URL loading, risking UI stalls during preview updates.
- **Resolution**:
  - Removed synchronous remote image loading from render pass.
  - Added async remote image warm queue with pending-key de-duplication and cache fill on completion.
  - Added renderer notification `OMMarkdownRendererRemoteImagesDidWarmNotification`; viewer now listens and schedules rerender.
  - Added renderer regression test to verify first-pass remote image rendering uses fallback text (non-blocking path).

## 35) Sprint-1 list continuation edge-case test coverage gap

- **Status**: Closed
- **Closed On**: 2026-02-18
- **Area**: Viewer / Source editor / Structured newline behavior
- **Description**: Sprint-1 lacked focused tests for task-list continuation, ordered-list incrementing, and quote-exit newline behavior.
- **Resolution**:
  - Added dedicated structured-newline test suite (`OMDSourceTextViewStructuredNewlineTests`).
  - Covered task-list continuation, empty task-list exit, ordered-list increment, and empty blockquote exit.

## 36) Phase-1 renderer global-state contamination risk

- **Status**: Closed
- **Closed On**: 2026-02-18
- **Area**: Renderer / Concurrency / State isolation
- **Description**: Renderer flow relied on process-global mutable `OMCurrent*` context variables, creating cross-render contamination risk under concurrent/mixed-option rendering.
- **Resolution**:
  - Removed mutable process-global render context (`OMCurrent*`) from `OMMarkdownRenderer`.
  - Introduced per-render context (`OMRenderContext`) passed through render helpers for parsing options, anchors/source lines, math perf accounting, layout width, and async-math mode.
  - Updated math/image/link/HTML policy resolution to consume per-render context rather than globals.
  - Added concurrent stress test coverage (`testConcurrentRenderersDoNotCrossContaminateRenderState`) to validate deterministic behavior under parallel mixed-policy renders.

## 37) GFM table preview parity and narrow-pane behavior

- **Status**: Closed
- **Closed On**: 2026-02-19
- **Area**: Renderer / GitHub parity / Preview layout
- **Description**: GitHub-flavored Markdown pipe tables lacked GitHub-like structure/styling and degraded badly in narrow/zoomed previews.
- **Resolution**:
  - Shipped attachment-based rich table rendering with GitHub-like header/background/border styling and inline markdown-in-cell rendering.
  - Switched table drawing to vector attachment cells and added pixel-snapped geometry to improve text clarity at non-integer zoom levels.
  - Enabled horizontal overflow behavior in preview (content-width growth + horizontal scrollbar) instead of stacked fallback for wide tables.
  - Fixed inline-code cell width clipping (including `printf("hello")`) by measuring real attributed cell content when computing column widths.
  - Added/updated renderer and table behavior tests; full test suite passes.
  - User confirmed UAT pass and requested closure.

## 38) Sprint-1 editing correctness closeout

- **Status**: Closed
- **Closed On**: 2026-02-19
- **Area**: Source editor UX / Formatting commands
- **Description**: Complete Sprint 1 hardening for deterministic source-editing behavior and formatting command coverage.
- **Resolution**:
  - Finalized deterministic editing behavior for:
    - list/quote `Enter` continuation and clean structure exit,
    - list `Tab` / `Shift+Tab` indent-outdent,
    - inline toggle two-press reversibility (`bold` / `italic` / `inline code`) across multiline, mixed, in-wrapper, and selected-word cases.
  - Added focused regression tests:
    - `OMDInlineToggleTests` for inline toggle reversibility,
    - expanded `OMDSourceTextViewTests` for shortcut routing and Vim interaction,
    - `OMDSourceTextViewStructuredNewlineTests` for structure continuation/exit.
  - Fixed shortcut dispatch gap where `Ctrl/Cmd+B` and `Ctrl/Cmd+I` could fail under GNUstep/Vim key paths:
    - source-editor standard shortcuts now preempt Vim handler for recognized formatting shortcuts,
    - control-character key variants are normalized,
    - added explicit Edit menu bindings for `Ctrl+B`/`Ctrl+I` as fallback dispatch path.
  - Full build and test suite remained green after fixes.
  - User confirmed UAT pass, including `Ctrl+B` and `Ctrl+I`.

## 39) Phase-1 UI polish follow-up (post-regression cleanup)

- **Status**: Closed
- **Closed On**: 2026-02-19
- **Area**: Viewer / Toolbar / Split UX
- **Description**: Finish final visual/interaction polish after Milestone 11 stabilization fixes.
- **Resolution**:
  - Verified zoom slider thumb/track visibility in the Sombre baseline and corrected rendering/interaction regressions uncovered during parity checks.
  - Completed GitHub-like table rendering polish, including table overflow behavior and inline content width handling in split preview.
  - Confirmed final toolbar alignment and control visibility in the stabilized Sombre configuration.
  - User confirmed UAT pass and approved closure of Issue #3.

## 40) Default GNUstep theme compatibility pass

- **Status**: Closed
- **Closed On**: 2026-02-19
- **Area**: Viewer / Theme compatibility / UAT
- **Description**: Validate and polish the app for the default GNUstep theme (separate from Sombre-focused polishing).
- **Resolution**:
  - Captured default-theme baseline previews and compared against the Sombre baseline for core split-preview workflows.
  - Fixed toolbar icon legibility in light/default theme by applying theme-aware tinting to custom toolbar icon assets using resolved control text color.
  - Verified no regressions in Sombre after the theme-aware icon update.
  - User requested closure of Issue #6.

## 41) Open source license alignment (GNUstep)

- **Status**: Closed
- **Closed On**: 2026-02-19
- **Area**: Project licensing
- **Description**: Align project licensing with GNUstep expectations while matching repository structure (reusable library + GUI application).
- **Resolution**:
  - Adopted split licensing by component:
    - `ObjcMarkdown/` library code uses `LGPL-2.1-or-later`.
    - `ObjcMarkdownViewer/` and `ObjcMarkdownTests/` use `GPL-2.0-or-later`.
  - Updated project-owned source headers from `Apache-2.0` SPDX identifiers to the component-appropriate SPDX identifiers above.
  - Replaced top-level `LICENSE` with a clear licensing map and added full license texts:
    - `LICENSES/LGPL-2.1.txt`
    - `LICENSES/GPL-2.0.txt`
  - Kept `third_party/` components under their upstream licenses (no relicensing of vendored dependencies).

## 42) Windows Sombre theme compatibility (feasibility + fallback)

- **Status**: Closed
- **Closed On**: 2026-02-20
- **Area**: Windows runtime / GNUstep theming / Compatibility
- **Description**: Determine why `GSTheme=Sombre` does not produce a usable window on Windows and establish a practical fix path.
- **Resolution**:
  - Chose a pragmatic compatibility path: default to `WinUXTheme` on Windows to avoid Sombre launch failures.
  - Kept Sombre opt-in via `OMD_USE_SOMBRE_THEME=1` for further investigation without blocking daily usage.
  - Documented the Windows Sombre crash symptom and the fallback in `WINDOWS_BUILD.md`.
  - Identified a likely root cause on MSYS2: Sombre built against a different `gnustep-base` DLL version than the app (`1_31` vs `1_30`).
  - Rebuilt and installed Sombre with the same toolchain so `Sombre.dll` links to `gnustep-base-1_30.dll`, restoring launch without the `NSConstantString ... forwardInvocation: ... hash` exception.
  - Verified UAT on Windows with the Sombre preference and successful relaunch.

## 43) GNOME dock identity + additional window launch ergonomics

- **Status**: Closed
- **Closed On**: 2026-03-02
- **Area**: Linux desktop integration / Multi-window UX
- **Description**: Running app showed a generic `GNUstep` dock icon/label in GNOME and lacked an obvious dock-level way to open additional windows.
- **Resolution**:
  - Added Linux desktop entry metadata to improve dock matching:
    - `StartupWMClass=GNUstep`
    - `X-GNOME-WMClass=MarkdownViewer`
    - `StartupNotify=true`
  - Added dock action support:
    - `Actions=NewWindow;` plus a `[Desktop Action NewWindow]` section in `Resources/MarkdownViewer.desktop.in`.
    - Desktop action executes launcher with `--new-window`.
  - Updated launcher scripts to accept and consume `--new-window`:
    - `scripts/omd-viewer.sh`
    - `scripts/omd-viewer-msys2.sh`
  - Added in-app multi-window command:
    - `File -> New Window` (`Cmd/Ctrl+N`) in `OMDAppDelegate`.
  - Set application icon image on startup from bundled `markdown_icon.png` so runtime icon presentation is explicit.

## 44) Split-view divider drift during window resize

- **Status**: Closed
- **Closed On**: 2026-03-02
- **Area**: Viewer / Split layout / Resize behavior
- **Description**: In Split mode, shrinking window width pushed the divider left and restoring width did not return the divider to the prior relative split.
- **Resolution**:
  - Stopped persisting split ratio during width-change resize events; ratio now persists only for divider-position changes at stable width.
  - Added internal guard state to distinguish programmatic divider updates from user-driven divider moves.
  - Kept stored split ratio stable across constrained window sizes so width restoration returns to expected relative divider position.
  - Removed mode-exit and window-close ratio persistence calls that could overwrite preferred ratio while the window is constrained.

## 45) Adwaita toolbar actions missing on GNUstep

- **Status**: Closed
- **Closed On**: 2026-03-12
- **Area**: Viewer / Toolbar / Theme compatibility
- **Description**: Under the Adwaita GNUstep theme, the viewer toolbar action icons were not drawing and the left side of the toolbar collapsed into empty space.
- **Resolution**:
  - Replaced the stock per-item toolbar buttons with a fixed custom segmented action strip so GNUstep renders the toolbar actions reliably.
  - Prepared toolbar images at a consistent small size before inserting them into the toolbar controls.
  - Verified the Adwaita toolbar now shows the Explorer, Open, Import, Save, Export, Print, and Preferences actions in the window chrome.

## 46) GNOME launcher failure in development checkout

- **Status**: Closed
- **Closed On**: 2026-03-12
- **Area**: Linux desktop integration / Launcher
- **Description**: Launching the app from GNOME could fail in a development checkout because local desktop entries and wrapper scripts were inconsistent.
- **Resolution**:
  - Restored executable permissions on the launcher wrapper scripts:
    - `scripts/omd-viewer.sh`
    - `scripts/omd-viewer-msys2.sh`
    - `scripts/install-desktop.sh`
  - Normalized `scripts/install-desktop.sh` back to LF line endings so desktop-entry reinstall works on Linux.
  - Updated the desktop entry template to invoke the wrapper through `bash`, making the launcher resilient even if the exec bit is lost again.
  - Updated `scripts/install-desktop.sh` to remove stale local desktop entries from this checkout and keep only the canonical `markdownviewer.desktop` launcher.

## 47) Preferences window too dense for Adwaita-style layout

- **Status**: Closed
- **Closed On**: 2026-03-21
- **Area**: Viewer / Preferences / Theme compatibility
- **Description**: The preferences window read as a long, dense scrolling form and did not fit the roomier Adwaita presentation the app now targets.
- **Resolution**:
  - Split preferences into native tab sections: `Appearance`, `Explorer`, `Preview`, and `Editor`.
  - Added a persisted layout-density preference with `Compact`, `Balanced`, and `Adwaita Style` modes so spacing can be tuned independently of the GNUstep theme.
  - Rebuilt the preferences panel around theme-aware card styling, roomier spacing, and section-specific copy.
  - Switched the preferences window to a fixed-width, pane-specific-height model with window-size clamping and per-pane scrolling when content exceeds the available screen height.
  - Restructured the editor accent-color controls to avoid cramped horizontal packing on narrower widths.

## 48) Toolbar icons rendered undersized after Adwaita toolbar refactor

- **Status**: Closed
- **Closed On**: 2026-03-21
- **Area**: Viewer / Toolbar / Theme compatibility
- **Description**: After the Adwaita toolbar work, the toolbar glyphs read noticeably too small relative to the surrounding controls.
- **Resolution**:
  - Increased toolbar control, label, and icon metrics so the chrome better matches the roomier Adwaita presentation.
  - Updated toolbar image preparation to trim transparent padding before scaling, restoring the apparent icon size without bloating the toolbar row.
  - Verified the adjusted toolbar proportions remain acceptable in Adwaita, Sombre, and the default GNUstep theme.

## 49) Split preview lagged divider changes and small-toolbar mode hid controls

- **Status**: Closed
- **Closed On**: 2026-03-21
- **Area**: Viewer / Split layout / Toolbar
- **Description**: The split preview page could remain detached from the divider during resize, and a follow-on toolbar compaction experiment caused the left-side custom controls to disappear under GNUstep.
- **Resolution**:
  - Restored regular GNUstep toolbar sizing so the custom action and mode controls render reliably.
  - Updated split-view resize handling to recompute preview geometry immediately instead of waiting for the debounced rerender path.
  - Left-anchored the preview page in Split mode with a small fixed gutter so the document no longer floats away from the divider.
  - Revalidated the main window from direct X11 window captures after relaunching the app under the Adwaita theme.

## 50) Formatting bar looked too dense for the Adwaita presentation

- **Status**: Closed
- **Closed On**: 2026-03-21
- **Area**: Viewer / Editor chrome / Theme compatibility
- **Description**: The source-editor formatting bar still read like a dense legacy glyph strip and made the Edit and Split modes look busier than the rest of the Adwaita-oriented window chrome.
- **Resolution**:
  - Changed the Adwaita-style default so the formatting bar stays hidden unless the user explicitly enables it.
  - Added a matching formatting-bar toggle to the Preferences editor section so the control is available outside the View menu.
  - Rebuilt the bar around grouped segmented controls so formatting actions stay visible without reading like a flat run of unrelated buttons.
  - Added adaptive bar layout so wider editor panes keep a single grouped row while narrower Split-mode widths reflow into two grouped rows instead of clipping or collapsing.
  - Revalidated both the calmer default state and the explicitly enabled formatting-bar state from fresh direct X11 window captures under the Adwaita theme.

## 51) Split-mode linked scrolling moved the preview in the opposite direction

- **Status**: Closed
- **Closed On**: 2026-03-21
- **Area**: Viewer / Split layout / Linked scrolling
- **Description**: In Split mode with linked scrolling enabled, moving the editor pane could send the preview pane in the opposite vertical direction.
- **Resolution**:
  - Stopped mixing clip-view and text-view coordinates when probing the top visible character for linked scrolling.
  - Updated split-sync scrolling to compute target positions in the text view's own coordinate system, then convert them back into the scrolled document view before applying the scroll.
  - Revalidated the fix in an isolated Split-mode session by paging the source pane forward and confirming the preview advanced into the same later sections instead of reversing direction.

## 52) Split-mode linked scrolling felt sticky and oscillatory

- **Status**: Closed
- **Closed On**: 2026-03-21
- **Area**: Viewer / Split layout / Linked scrolling
- **Description**: Even after the direction fix, linked scrolling in Split mode could wait too long before moving the follower pane and then over-correct in visible jumps.
- **Resolution**:
  - Switched live linked scrolling from the very top visible glyph to a viewport anchor lower in the pane so the follower tracks a more stable reading position.
  - Added a short-lived scroll-driver lock so only the pane the user is actively moving leads during a live scroll burst.
  - Added a small pixel deadband before applying follower scroll updates, reducing tiny corrective hops that made the preview appear to chatter.
  - Rebuilt and reran the full test suite, then spot-checked the new Split-mode behavior in an isolated Adwaita session.

## 53) Split-mode trackpad scrolling lagged badly on large documents

- **Status**: Closed
- **Closed On**: 2026-03-21
- **Area**: Viewer / Split layout / Linked scrolling / Performance
- **Description**: Large documents could scroll smoothly in Read and Edit modes, but Split mode became noticeably laggy on trackpad input because live linked scrolling was doing too much work on every small bounds-change event.
- **Resolution**:
  - Added a small line-info cache inside the preview-sync layer so repeated mapping probes stop reparsing the same source and preview text buffers during live scrolling.
  - Changed the block-anchor mapping path to use the cheaper anchor-based route first and only fall back to the slower full-text matcher when anchors are unavailable or invalid.
  - Replaced the line-location lookup walk with a binary search so repeated live sync probes scale better on larger documents.
  - Rebuilt the app and reran the full test suite after the sync-layer optimization pass.

## 54) Preferences toolbar icon did not match the bundled icon set

- **Status**: Closed
- **Closed On**: 2026-03-21
- **Area**: Viewer / Toolbar / Visual consistency
- **Description**: The preferences action was still using a stock GNUstep image, so it looked out of place beside the custom bundled toolbar icons.
- **Resolution**:
  - Generated a new dedicated preferences/settings symbol using the OpenAI image API with the existing toolbar assets as style references.
  - Normalized the generated glyph into the same transparent pale monochrome treatment used by the rest of the toolbar icon set.
  - Added the new `toolbar-preferences.png` asset to the app bundle and updated both toolbar code paths to prefer it over the stock GNUstep fallback image.

## 55) Preferences theme menu omitted the built-in GNUstep theme

- **Status**: Closed
- **Closed On**: 2026-03-21
- **Area**: Viewer / Preferences / Theme selection
- **Description**: The theme popup only listed discovered `.theme` bundles plus a misleading `System Default` entry, so the built-in GNUstep theme was not shown explicitly even though GNUstep treats it as the canonical default theme.
- **Resolution**:
  - Updated the theme popup to label the built-in default as `GNUstep`, matching GNUstep's own preferences pane semantics.
  - Kept the existing behavior where selecting `GNUstep` clears the `GSTheme` preference instead of writing a bundle name.
  - Filtered any discovered `GNUstep.theme` bundle names out of the scanned theme list to avoid duplicate menu entries if such a bundle is present.

## 56) Selecting GNUstep from the theme menu did not actually revert the theme

- **Status**: Closed
- **Closed On**: 2026-03-21
- **Area**: Viewer / Preferences / Theme selection
- **Description**: Choosing `GNUstep` in the app's theme popup only cleared the app-local `GSTheme` value, so an existing global `NSGlobalDomain` theme like `Adwaita` still won on the next launch and the UI did not revert to the built-in GNUstep theme.
- **Resolution**:
  - Changed theme preference reads to check `NSGlobalDomain` first, matching where GNUstep's own preferences pane persists `GSTheme`.
  - Updated theme writes so named themes are stored in `NSGlobalDomain`.
  - Updated the `GNUstep` path to clear both the app-local copy and the global `GSTheme` key, then synchronize defaults immediately.

## 57) Empty Split preview could draw a stray page fragment with no document open

- **Status**: Closed
- **Closed On**: 2026-03-21
- **Area**: Viewer / Split layout / Empty state
- **Description**: When the viewer opened in Split mode with no current document, the preview pane could still draw a small leftover page fragment because the preview surface styling and overlay state were initialized before any render and never explicitly cleared for the no-document state.
- **Resolution**:
  - Added a shared preview-clear path that blanks the preview text storage, removes copy/code-block overlay subviews, clears document-surface styling, and resets the preview canvas to the visible clip bounds.
  - Applied that clear path during preview setup, any render attempt with no preview markdown, and any document transition to `nil`.
  - Removed the redundant last-tab-close preview cleanup that could accidentally repopulate stale overlay controls from the previous render state.

## 58) Newly opened documents could inherit the previous document's bottom scroll position

- **Status**: Closed
- **Closed On**: 2026-03-21
- **Area**: Viewer / Document opening / Initial viewport
- **Description**: Opening a different document could leave the source and preview panes scrolled to the previous document's old viewport, which often meant the new file appeared at the bottom on open.
- **Resolution**:
  - Added a targeted post-open viewport reset so freshly opened documents start at the beginning instead of inheriting stale editor/preview scroll state.
  - Reset the source selection to location `0` and scrolled the visible source/preview clip views back to the top as part of the document-open path.
  - Kept existing-tab selection behavior unchanged by limiting the reset to the fresh open/replace flow rather than applying it to every tab switch.

## 59) Scroll speed was effectively fixed at GNUstep's slow default

- **Status**: Closed
- **Closed On**: 2026-03-21
- **Area**: Viewer / Preferences / Scrolling
- **Description**: The app was inheriting GNUstep `NSScrollView`'s default line-scroll step, which made wheel and trackpad scrolling feel much slower than other desktop apps.
- **Resolution**:
  - Added a new `Scroll Speed` slider to the Appearance preferences section.
  - Persisted the setting in app defaults and applied it live to the source, preview, and explorer scroll views via GNUstep's native `verticalLineScroll` / `horizontalLineScroll` APIs.
  - Increased the app's shipped default above GNUstep's stock `10` point line step so scrolling feels less glacial out of the box while still keeping the GNUstep-native mechanism.

## 60) Read-mode preview could leave overlapping ghost copies during window resize

- **Status**: Closed
- **Closed On**: 2026-03-22
- **Area**: Viewer / Preview layout / Resize redraw
- **Description**: Resizing the window in preview-visible modes could sometimes leave an old copy of the rendered page behind the newly laid-out preview, making it look like two versions of the document were overlapping.
- **Resolution**:
  - Replaced the plain preview canvas container with an opaque fill view so old preview pixels are actively cleared instead of relying on a transparent document-view background.
  - Marked the union of the old and new preview-page frames dirty whenever the preview page is resized or re-centered, forcing GNUstep to repaint the area that previously held the stale copy.
  - Rebuilt the app and reran the full GNUstep test bundle after the preview-canvas redraw fix.

## 61) GitHub explorer list could overlap the sidebar header controls

- **Status**: Closed
- **Closed On**: 2026-03-22
- **Area**: Viewer / Explorer sidebar / GitHub mode layout
- **Description**: In GitHub explorer mode, the file list scroll view could be laid out slightly too high, which let it paint over the bottom edge of the `Up` button and repository path label and made the top of the list/header area look clipped.
- **Resolution**:
  - Replaced the fixed list-height math with a layout derived from the actual `Up` button and path-label frames, so the scroll view always starts below the visible header controls.
  - Removed the forced 80-point minimum list height in this path so a shorter window shrinks the list instead of reintroducing overlap.
  - Rebuilt the app and reran the full GNUstep test bundle after the explorer-sidebar layout fix.

## 62) Short preview documents could collapse to a short card instead of using a full-height reading surface

- **Status**: Closed
- **Closed On**: 2026-03-22
- **Area**: Viewer / Preview layout / Read mode resizing
- **Description**: In read mode, short documents could open or resize into a short white card instead of filling the visible reading surface because the preview geometry could be measured against stale clip bounds and the preview text view could shrink itself back down to content height.
- **Resolution**:
  - Forced the preview scroll view to refresh its clip geometry before width and height measurements so initial opens, mode switches, and read-pane resizes use the current viewport instead of stale pre-tile bounds.
  - Flipped the preview canvas view so the reading surface is top-aligned inside the scroll view.
  - Disabled automatic horizontal and vertical resizing on the preview text view so the preview layout code, not GNUstep text view autosizing, owns the visible document surface size.
  - Rebuilt the app and reran the full GNUstep test bundle after the read-mode preview alignment fix.

## 63) Disabled toolbar actions could still look active in the segmented icon group

- **Status**: Closed
- **Closed On**: 2026-03-22
- **Area**: Viewer / Toolbar / Disabled-state affordance
- **Description**: In the primary segmented toolbar controls, disabled actions such as `Save` could still render with the same dark icon tint as enabled actions, which made them look clickable even when the control logic had already disabled them.
- **Resolution**:
  - Added an explicit toolbar-image tinting helper so segmented control icons can be redrawn with a muted disabled color instead of relying on GNUstep to dim pre-tinted images.
  - Applied that disabled tint to `Save`, `Export PDF`, and `Print` whenever those actions are unavailable.
  - Rebuilt the app and reran the full GNUstep test bundle after the toolbar disabled-state fix.

## 64) Read -> Split -> Read could restore the wrong document position

- **Status**: Closed
- **Closed On**: 2026-03-22
- **Area**: Viewer / Mode switching / Scroll-position preservation
- **Description**: Switching from Read to Split and back to Read could jump the document to an unrelated position, often near the bottom, because mode transitions were restoring from selection-based anchors instead of the visible preview/source viewport.
- **Resolution**:
  - Changed transitions out of Read mode to capture the visible preview viewport anchor instead of the preview selection location.
  - Changed Split -> Read transitions to capture the visible source viewport anchor, and used explicit viewport-anchored scrolling when restoring source/preview positions during the mode change.
  - Rebuilt the app and reran the full GNUstep test bundle after the mode-transition scroll preservation fix.

## 65) Explorer parent-navigation button could render like a clipped dot

- **Status**: Closed
- **Closed On**: 2026-03-22
- **Area**: Viewer / Explorer sidebar / Header controls
- **Description**: The small header button used to move to the parent folder or repository path could render unclearly under GNUstep, sometimes looking like a clipped `.` instead of a readable label.
- **Resolution**:
  - Replaced the text label with a compact icon-only parent-navigation button so the control no longer depends on theme-specific button text rendering.
  - Tinted and disabled the button when the explorer is already at its root path, so its visual state matches whether navigation is possible.
  - Rebuilt the app and reran the full GNUstep test bundle after the explorer parent-button fix.

## 66) GNUstep startup still emitted residual negative-width warnings from the hidden tab strip

- **Status**: Closed
- **Closed On**: 2026-03-22
- **Area**: Viewer / Window chrome / Initial layout
- **Description**: Launching the viewer under GNUstep could still emit a couple of `NSView setFrame: given negative width` warnings during startup because the hidden zero-height tab strip was left with an autoresizing mask that GNUstep could drive into invalid geometry during the earliest workspace layout passes.
- **Resolution**:
  - Traced the remaining warnings to the app-owned `TabStripView` rather than GNUstep window decorations.
  - Switched the tab strip to fully manual layout and collapse it to `NSZeroRect` whenever the strip is not visible, instead of leaving a hidden zero-height autoresizing view in the hierarchy.
  - Rebuilt the app, verified a clean startup launch with no remaining negative-width warnings, and reran the full GNUstep test bundle.

## 67) Automated Windows MSI packaging pipeline (GNUstep runtime included)

- **Status**: Closed
- **Closed On**: 2026-03-26
- **Area**: Release engineering / Windows packaging / CI-CD
- **Description**: Build automated GitHub pipelines that produce a usable Windows MSI for the MSYS2/clang GNUstep build, including all required runtime components.
- **Resolution**:
  - Updated [windows-packaging.yml](/C:/Users/Support/git/ObjcMarkdown/.github/workflows/windows-packaging.yml) so pushed `v*` tags build MSI and portable ZIP artifacts on `windows-latest` without blocking on the separate self-hosted Linux workflow.
  - Hardened runtime staging in [stage-runtime.sh](/C:/Users/Support/git/ObjcMarkdown/scripts/windows/stage-runtime.sh) so MSYS2 `clang64` runtime DLL collection no longer assumes one specific compiler-runtime layout on GitHub runners.
  - Verified tagged CI artifact production on `2026-03-26` from tag `v0.1.1-rc2`:
    - Actions run: `23612901170`
    - Result: success
    - Uploaded artifact bundle: `objcmarkdown-windows-0.1.1`
  - Completed clean-machine OCI validation against the CI-produced MSI `ObjcMarkdown-0.1.1.0-win64.msi` from that run:
    - fresh OCI VM launched from the golden image,
    - temporary narrow SSH ingress applied automatically during validation,
    - MSI install succeeded,
    - smoke launch succeeded,
    - uninstall succeeded,
    - logs collected under `dist/oci-logs/ci-23612901170`,
    - disposable VM terminated after the run.
  - Hardened [oci-run-msi-validation.ps1](/C:/Users/Support/git/ObjcMarkdown/scripts/windows/oci-run-msi-validation.ps1) to manage temporary SSH-ingress narrowing/restoration and to tolerate native `ssh`/`scp` output while still returning a structured result object.

## 68) External-tool display math could fall back to literal LaTeX for multi-line `cases` blocks

- **Status**: Closed
- **Closed On**: 2026-03-25
- **Area**: Renderer / Math / External tools
- **Description**: Multi-line display-math blocks were reconstructed from cmark text literals, which meant CommonMark escaping could collapse source `\\` row separators down to `\`. LaTeX environments such as `cases` then failed to compile, so those formulas fell back to styled literal text while simpler equations still rendered as attachments.
- **Resolution**:
  - Rebuilt multi-node display-math formulas from cmark source-position slices instead of only using normalized text literals, preserving raw TeX row separators from the markdown source.
  - Added block-level recovery for `$$...$$` ranges directly from source lines so display math still renders when cmark reinterprets interior lines as setext headings or inline emphasis.
  - Kept the existing literal-text fallback when source-position recovery is unavailable, so the renderer still degrades safely if source positions are missing.
  - Added renderer regression coverage for external-tools display math covering `cases` blocks, bare `-` lines, and `q^*` content.
  - Rebuilt the library, app, and test bundle after the math-rendering fix.

## 69) PDF export ignored the active math-rendering mode and fell back to styled text

- **Status**: Closed
- **Closed On**: 2026-03-25
- **Area**: Viewer / Export / PDF
- **Description**: The print/PDF export path created a fresh markdown renderer with default parsing options. Since the default math policy is `StyledText`, exports could drop external-tool LaTeX attachments even when the live preview was configured to render formulas as images.
- **Resolution**:
  - Changed the print/export renderer to clone the active preview renderer's parsing options instead of starting from defaults.
  - Preserved the user's current math-rendering policy and related parsing settings for print and PDF export.
  - Rebuilt the app and reran the full GNUstep test bundle after the export fix.

## 70) Linux AppImage clean-Debian backend initialization failure

- **Status**: Closed
- **Closed On**: 2026-03-27
- **Area**: Release engineering / Linux packaging / GNUstep runtime
- **Description**: The March 26 AppImage failed to initialize the GNUstep backend on a clean Debian guest. Host-side packaging was then tightened to remove build-tree path leakage and the rebuilt AppImage was revalidated directly inside the Debian validation VM.
- **Resolution**:
  - Updated [GNUmakefile](/home/danboyd/git/ObjcMarkdown/ObjcMarkdownViewer/GNUmakefile) so the packaged viewer binary uses only packaged-relative runtime lookup instead of repo-local build-tree `RUNPATH` entries.
  - Hardened [validate-appimage.sh](/home/danboyd/git/ObjcMarkdown/scripts/linux/validate-appimage.sh) to reject packaged ELFs whose `RPATH` or `RUNPATH` escapes the AppDir/AppImage and to correctly validate extracted AppImages referenced by relative path.
  - Updated [linux-appimage.yml](/home/danboyd/git/ObjcMarkdown/.github/workflows/linux-appimage.yml) so the `linuxdeploy` step resolves the staged runtime through exported `LD_LIBRARY_PATH` rather than ambient host library state.
  - Rebuilt the AppImage locally and validated the March 27 artifact on the host:
    - `dfb7c0e57df82061efc4660d5982343301c9db69022d20023f0048234f3cb3bb`
  - Took a libvirt revert point for the Debian validation VM on hypervisor `iep-vm2` before guest testing:
    - domain: `iep-appimage-test`
    - snapshot: `pre-appimage-validation-2026-03-27`
  - Verified from inside the Debian VM that the packaged backend bundle exists and its dependency closure resolves from the extracted AppImage runtime.
  - Confirmed the guest has no ambient GNUstep install:
    - `/usr/GNUstep` absent
    - no `defaults` tool on `PATH`
  - Launched the March 27 AppImage inside the guest GNOME session with `--GNU-Debug=BackendBundle` and confirmed it loads the packaged backend from the extracted AppImage path:
    - `Loading Backend from /tmp/appimage_extracted_.../usr/GNUstep/System/Library/Bundles/libgnustep-back-032.bundle`
  - Confirmed the GUI stayed running in the guest until explicitly terminated after the smoke window, which closes the earlier clean-Debian startup failure.

## 71) Linux AppImage PDF export failed because the shared export helper was compiled out

- **Status**: Closed
- **Closed On**: 2026-03-27
- **Area**: Viewer / Export / PDF / Linux AppImage
- **Description**: The AppImage's `Export as PDF` path had been refactored to use a shared `exportDocumentAsPDFToPath:` helper, but that method body was still inside a Windows-only preprocessor section. The Linux build therefore shipped without the selector, so the packaged viewer raised `does not recognize exportDocumentAsPDFToPath:` when export was triggered.
- **Resolution**:
  - Moved `exportDocumentAsPDFToPath:` out of the Windows-only region in [OMDAppDelegate.m](/home/danboyd/git/ObjcMarkdown/ObjcMarkdownViewer/OMDAppDelegate.m) so both Linux and Windows builds include the shared export implementation.
  - Kept the platform-specific PDF backends inside the method:
    - Windows continues to use the headless-browser HTML-to-PDF path.
    - Linux continues to use `NSPrintOperation` with `NSPrintSaveJob`.
  - Rebuilt the viewer, reran the full GNUstep `xctest` bundle, rebuilt the AppImage, and revalidated the package on the host.
  - Verified inside the Debian AppImage validation VM that the rebuilt AppImage now exports a real PDF successfully:
    - AppImage SHA-256: `b6bb9bb3c812397e3aa3d29640e5a633f47b825547045b8e65f9983bc6b16482`
    - Exported file: `/tmp/omd-export-automated.pdf`
    - Result: PDF 1.7, 2 pages, 41077 bytes

## 72) Linux AppImage omitted GNUstep system image resources, breaking themed menu/control glyphs

- **Status**: Closed
- **Closed On**: 2026-03-27
- **Area**: Release engineering / Linux packaging / GNUstep UI resources
- **Description**: The AppImage bundled the GNUstep theme library and GUI/backend shared libraries, but it did not stage `/usr/GNUstep/System/Library/Images`. That directory contains core GNUstep UI artwork such as `GNUstepMenuImage.tiff`, submenu arrows, and switch/check state images. Without it, the packaged Adwaita UI fell back to incorrect or missing glyphs, including bullet-like indicators where checkmarks should render and missing submenu arrows in the `Export` menu.
- **Resolution**:
  - Updated [stage-appimage-runtime.sh](/home/danboyd/git/ObjcMarkdown/scripts/linux/stage-appimage-runtime.sh) to bundle `/usr/GNUstep/System/Library/Images` into the AppDir/AppImage.
  - Updated [validate-appimage.sh](/home/danboyd/git/ObjcMarkdown/scripts/linux/validate-appimage.sh) to fail packaging validation when key GNUstep image assets are missing:
    - `GNUstepMenuImage.tiff`
    - `common_ArrowRight.tiff`
    - `common_SwitchOn.tiff`
    - `common_SwitchOff.tiff`
  - Rebuilt and revalidated the AppDir and AppImage after the packaging fix.
  - Verified in the Debian VM that the rebuilt AppImage now extracts those image resources correctly.
  - Rebuilt AppImage SHA-256: `6cc632e5046bc0d050de28a7128fbdd9ccdeda70b630cd63d69c3021d3cc0ba9`

## 73) Launching with a document could show a transparent shell window before content appeared

- **Status**: Closed
- **Closed On**: 2026-04-06
- **Area**: Viewer / Launch / Window presentation
- **Description**: The viewer presented its main window from `setupWindow` before launch-time document opening finished. When a document was supplied at launch, the app could show a title bar and transparent or unpainted content area while synchronous open/render work still occupied the main thread.
- **Resolution**:
  - Added an explicit launch overlay so startup can paint a stable loading state immediately instead of showing an empty or transparent content region.
  - Deferred launch-time document open and recovery handling to the next run-loop turn after first window presentation, giving GNUstep a chance to draw the loading state before synchronous file-open and preview-render work begins.
  - Moved explorer population and related nonessential window startup work out of the initial first-paint path so the window becomes visible sooner.
  - Preserved secondary-window behavior by presenting empty windows immediately and scheduling deferred post-presentation explorer setup separately.
  - Rebuilt the GNUstep app and test bundle after the launch-presentation change.

## 74) Lower-level OCI Windows validation script drifted from the supported OracleTestVMs contract

- **Status**: Closed
- **Closed On**: 2026-04-14
- **Area**: Windows release validation / OCI automation
- **Description**: The repo still exposed a lower-level direct-OCI Windows validation path that had drifted from the supported `OracleTestVMs` bootstrap and access model, encouraging stale SSH assumptions and duplicate validation contracts.
- **Resolution**:
  - Retired [oci-run-msi-validation.ps1](/home/danboyd/git/ObjcMarkdown/scripts/windows/oci-run-msi-validation.ps1) as a supported path and changed it to fail fast with a redirect to the `OracleTestVMs` helper.
  - Updated Windows validation docs to make [windows-otvm-msi-validation.md](/home/danboyd/git/ObjcMarkdown/docs/windows-otvm-msi-validation.md) the only supported clean-machine Windows validation workflow.
  - Reframed [windows-oci-msi-validation.md](/home/danboyd/git/ObjcMarkdown/docs/windows-oci-msi-validation.md) as a retirement note rather than an active operator guide.
  - Updated repo docs so Windows clean-machine validation consistently points at [otvm-msi-validation.sh](/home/danboyd/git/ObjcMarkdown/scripts/windows/otvm-msi-validation.sh) instead of the old direct-OCI helper.

## 75) Tagged Linux AppImage release flow blocked by missing self-hosted GitHub runner

- **Status**: Closed
- **Closed On**: 2026-04-21
- **Area**: Release engineering / GitHub Actions / Linux packaging
- **Description**: The tagged Linux AppImage workflow was configured for a self-hosted GNUstep runner label set, but no matching runner was registered, so hosted release packaging could not start.
- **Resolution**:
  - Moved `linux-appimage` back to the reusable `gnustep-packager` hosted AppImage workflow path.
  - Kept ObjcMarkdown's Linux preflight limited to app-owned setup such as preparing the Adwaita theme checkout.
  - Updated Linux staging to consume the managed `gnustep-cli-new` runtime layout, including GNUstep libraries and resources under `Local/Library`.
  - Treated absent PreferencePanes runtime payloads as optional because the managed Linux toolchain does not ship them and ObjcMarkdown does not require them.
  - Switched hosted AppImage smoke validation to `marker-file` mode and added an app-side smoke marker hook so GitHub-hosted headless validation does not require an X display.
  - Verified the normal hosted Linux AppImage workflow on `2026-04-21`:
    - workflow run: `24743212445`
    - commit: `96cd011f1f024c47ba26bda9724dad9ffd3421cb`
    - result: build, stage, package, runtime-closure validation, and smoke validation passed

## 76) Hosted Windows `gnustep-cli-new` MSI bootstrap hung before diagnostics

- **Status**: Closed
- **Closed On**: 2026-04-21
- **Area**: Release engineering / Windows packaging / `gnustep-packager` / `gnustep-cli-new`
- **Description**: The reusable Windows MSI workflow could remain indefinitely in `Bootstrap And Smoke Test gnustep-cli-new For MSI` before ObjcMarkdown build/stage started, and GitHub did not expose live logs for that active step.
- **Resolution**:
  - Patched upstream `gnustep-packager` through commit `3c10f1a2c8f976cc30aaaa4f85f6a14b74ebb562` so the hosted Windows bootstrap runs through bounded native processes, collects stdout/stderr logs, kills the bootstrap process tree on timeout, and smokes the generated `HelloPackager.exe` directly until the public `gnustep-cli-new` Windows CLI artifact is refreshed.
  - Pinned ObjcMarkdown's Linux and Windows packaging workflows to that packager commit.
  - Verified the diagnostic path in hosted Windows run `24746538617`, which uploaded setup/build/run logs and isolated the stale published CLI artifact's `.exe` lookup issue.
  - Verified the bootstrap gate passed in hosted Windows runs `24747049925` and `24747383333`; the remaining Windows MSI blocker has moved to app-side WinUITheme/build/stage packaging and remains tracked under the Windows MSI rebuild handoff issue.

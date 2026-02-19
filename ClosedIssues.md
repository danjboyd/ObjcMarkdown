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

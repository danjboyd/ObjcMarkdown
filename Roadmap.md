# ObjcMarkdown World-Class Markdown Editor Roadmap

## Snapshot (2026-02-17)

This roadmap converts current open issues and the latest technical audit into an execution plan toward a world-class Markdown editor.

Current baseline:
- Build is green on GNUstep.
- Test suite is green.
- Core product is a hybrid editor/viewer with split sync, preferences, syntax highlighting, import/export, and math modes.
- Full-fidelity WYSIWYG round-trip is not implemented yet.
- HTML document import/export is available through Pandoc when installed.

## Status Update (2026-02-18)

Completed since prior snapshot:
- Phase 0 safety goals are implemented (remote image non-blocking warm path + link scheme allowlist).
- Phase 1 renderer-concurrency/state-isolation goals are implemented:
  - removed process-global mutable render context in `OMMarkdownRenderer`,
  - introduced per-render context passed through render helpers,
  - added concurrent render stress coverage for mixed parsing-option workloads.
- Full build + test suite remain green after the refactor.

## End-of-Day Handoff (2026-02-19)

Completed today:
- Started GitHub table-parity implementation for pipe tables (`| ... |`) in preview.
- Added a dedicated validation fixture: `TableRenderDemo.md`.
- Added/updated renderer tests to exercise structured table output, narrow-layout fallback behavior, and inline markdown in cells.
- Build + tests pass locally with GNUstep workflow.

Current gap:
- Table parity slice is complete and closed (see `ClosedIssues.md` issue 37).

Morning restart checklist:
1. `source /usr/GNUstep/System/Library/Makefiles/GNUstep.sh`
2. `gmake`
3. `mkdir -p ~/GNUstep/Defaults/.lck`
4. `MALLOC_CHECK_=0 LD_LIBRARY_PATH=$PWD/ObjcMarkdown/obj:/usr/GNUstep/System/Library/Libraries xctest ObjcMarkdownTests/ObjcMarkdownTests.bundle`
5. `gmake run TableRenderDemo.md`
6. Validate table parity in split preview and while narrowing the preview pane.

Definition of done for this slice:
- Preview table structure visually matches GitHub much more closely (header row, borders, cell spacing/alignment).
- Narrow pane behavior remains readable (degrade gracefully instead of collapsing/distorting).
- Automated tests stay green after final renderer adjustment.

## End-of-Day Status (2026-02-17)

Completed today:
- Adaptive zoom behavior: real-time slider updates with automatic fallback to debounced rendering on slow documents.
- Split-layout regression fix: `Edit -> Split` now restores split pane layout immediately (no resize required).
- Source editor list `Tab` / `Shift+Tab` indent-outdent behavior added.
- Inline toggle hardening (`bold` / `italic` / `inline code`) for deterministic behavior on multiline and mixed selections.
- Added source-editor list indentation tests (`OMDSourceTextViewTests`) and kept full test suite green.

Current roadmap position:
- Sprint 1 editing-correctness closeout is complete (see `ClosedIssues.md` issue 38).
- Sprint 2 and Sprint 3 remain queued after Sprint 1 acceptance criteria are fully met.

Remaining work to finish Sprint 1:
- All Sprint 1 acceptance items are satisfied and test/UAT-validated.

## Formatting Bar Initiative (2026-02-17)

Goal: add a first-rate, source-first Markdown formatting bar that feels instantly familiar to users of popular editors while preserving deterministic Markdown edits.

Agreed product decisions:
- Architecture: source-first (WYSIWYM), not rich-text editing.
- Placement: in source editor pane only; hidden in `Read` mode.
- Visibility: shown in `Edit` and `Split`; toggle in `View -> Show Formatting Bar`.
- Platform strategy: custom in-window bar for GNUstep/Windows/macOS parity.
- Baseline visual language: neutral GitHub-like grouped controls with subtle active/hover states.

V1 command surface:
- Inline: bold, italic, strike, inline code, link, image.
- Block: heading dropdown (`Paragraph`, `H1`-`H6`), blockquote, fenced code block, horizontal rule.
- Lists: bullet, numbered, task list.
- Insert: table.

V1 interaction rules:
- Selection present: wrap/transform selected text or lines.
- No selection: insert snippet/placeholder and place caret on editable placeholder.
- Single undo transaction per command.
- Tooltips include keyboard shortcut hints where applicable.
- Active-state highlighting based on caret/selection context.

V1 typing assists:
- `Enter` continues bullet/number/task/blockquote lines.
- `Enter` on empty list/quote line exits that structure.
- `Tab`/`Shift+Tab` list indent/outdent (follow-up after initial command bar landing).

Delivery phases:
1. Foundation:
- Add source-pane formatting bar container and mode-aware visibility.
- Add view-menu toggle + preference persistence.
2. Commands:
- Implement toolbar command actions and snippet transforms.
- Add undo grouping and selection/caret placement rules.
3. Context + Assists:
- Add active-state detection for major inline/block contexts.
- Add smart newline continuation/exit behavior.
4. Polish:
- Final visual tuning, spacing, hover/pressed states, accessibility checks.
- Add focused tests for transform rules and smart newline behavior.

Current implementation status (started):
- Done: source-pane formatting bar container wired into `Edit` and `Split`.
- Done: `View -> Show Formatting Bar` toggle added with persisted preference.
- Done: V1 command handlers implemented for inline wraps, links/images, heading levels, lists, blockquote, fenced code, table, and horizontal rule.
- In progress: visual polish (button hierarchy, compact labels/icons, spacing refinements).
- Next: typing assists (`Enter` continuation/exit, `Tab`/`Shift+Tab` indent/outdent) and focused tests for transform behavior.

## Next 3 Sprints (Locked Execution Plan)

### Sprint 1: Editing Correctness and Flow (in progress)

Primary goal:
- Make source editing behavior feel predictably "native" for Markdown power users.

Scope:
- List continuation/exit hardening for bullet, ordered, task, and blockquote lines.
- `Tab` / `Shift+Tab` list indent-outdent behavior in source editor.
- Tighten inline toggle behavior (`bold`, `italic`, `code`) on mixed selections.
- Add focused tests for newline/list indentation behavior.

Acceptance criteria:
- Pressing `Enter` at end of list/quote line continues expected structure.
- Pressing `Enter` on empty structure line exits cleanly.
- `Tab` indents selected list lines; `Shift+Tab` outdents them.
- Toggle commands are reversible and deterministic across repeated presses.
- New editor behavior is covered by automated tests.

Status update:
- Started: implemented source-editor list `Tab` / `Shift+Tab` indentation path and added first tests.
- Started: hardened inline toggle behavior for multiline/mixed selections with deterministic two-press reversibility.

### Sprint 2: Regression Harness and Stability

Primary goal:
- Prevent repeat regressions in the interaction model.

Scope:
- Add mode-transition layout tests (`Read`/`Edit`/`Split`) and split-pane assertions.
- Add adaptive zoom behavior tests (real-time vs debounce fallback).
- Add command-focused tests for formatting bar transforms and undo grouping.
- Add basic UI capture script for repeatable visual checks.

Acceptance criteria:
- Previously fixed regressions are reproducibly test-covered.
- A failing split-layout/zoom/command behavior blocks merge.
- Visual baseline capture exists for critical screens.

### Sprint 3: GitHub-Parity UX Pass

Primary goal:
- Close the most visible gaps versus mainstream Markdown editors.

Scope:
- Final code block styling parity (padding, border tone, copy affordance polish).
- Copy interaction polish: consistent hover cursor, top-right placement, feedback timing.
- Toolbar and icon polish pass (resolution, alignment, consistency across themes).
- Close remaining Phase-1 polish follow-up items in `OpenIssues.md`.

Acceptance criteria:
- Side-by-side parity checklist against GitHub test fixtures passes for core blocks.
- UI review screenshots show no known high-visibility polish defects.
- Open Phase-1 polish issue is closed or reduced to explicit deferred items.

## North Star

Deliver a Markdown editor that is:
- Fast under real-world documents.
- Safe by default.
- Reliable across GNUstep/macOS environments.
- Faithful in Markdown round-trip behavior.
- Polished enough for daily professional writing workflows.

## Guiding Priorities

1. Stability and safety before feature expansion.
2. Performance guardrails before deeper WYSIWYG investment.
3. Deterministic data model for any future visual editing.
4. Incremental delivery with measurable acceptance criteria.

## Phase Plan

## Phase 0: Safety and Blocking Risk Removal (P0)

Goal: remove the highest-risk behaviors that can block responsiveness or create unsafe defaults.

Scope:
- Replace synchronous image fetching during render with async/background loading and staged preview updates.
- Add URL scheme allowlist and safer link-opening policy (with clear handling for unsupported schemes).
- Preserve remote-image policy defaults and make behavior explicit in UI/help text.
- Keep math/image/link behavior covered by tests during refactor.

Acceptance criteria:
- No UI stall from slow image/network fetch during typing or split preview updates.
- Links with unsupported or unsafe schemes do not launch silently.
- Existing tests remain green; add coverage for scheme allowlist behavior.

## Phase 1: Renderer Concurrency and State Isolation (P0, Completed 2026-02-18)

Goal: make rendering re-entrant and predictable.

Scope:
- Remove process-global mutable render context state from renderer flow.
- Introduce per-render context object/state passed through render pipeline.
- Audit math async artifact notifications for cross-render contamination risk.
- Add concurrency stress tests for repeated renders and mode switches.

Acceptance criteria:
- No shared mutable global state in render path.
- Repeated render operations produce deterministic results under stress.
- No regressions in block anchors, code ranges, or math artifact updates.

## Phase 2: Performance Hardening (P1)

Goal: keep large documents responsive.

Scope:
- Optimize line-number ruler to avoid repeated O(n) scans for visible lines.
- Add indexes/cached line starts for source text operations used by scrolling and line display.
- Add benchmark tests for large source documents and split sync scenarios.
- Define performance budgets for render, apply, and post-layout stages.
- Implement inline/block HTML preview rendering strategy (deferred from earlier phases):
  - move beyond current `RenderAsText` fallback,
  - keep behavior safe-by-default via explicit sanitization/allowlist policy,
  - preserve deterministic fallback text for unsupported tags.

Acceptance criteria:
- Smooth scrolling and stable line numbers in large documents.
- Measured improvement in large-doc scenarios.
- Performance tests/checks run in CI or pre-release validation workflow.
- Inline/block HTML rendering behavior is explicit, safe, and test-covered.

## Phase 3: UI Regression Automation and Polish Closure (P1)

Goal: close remaining phase-1 polish items and prevent regressions.

Scope:
- Finish open polish items:
  - Zoom slider visibility across themes.
  - Toolbar vertical alignment consistency.
  - Decision on default toolbar inclusion of Preferences.
  - Optional preview softening via safe draw path only.
- Add automated UI regression checks for split-pane hierarchy/layout.
- Add screenshot capture harness for repeatable before/after validation.

Acceptance criteria:
- Remaining UI polish checklist is complete.
- Split-pane regressions are detectable by tests/screenshots before merge.
- Visual baseline artifacts are versioned and reviewed during UI changes.

## Phase 4: Syntax Highlighting Architecture Expansion (P2)

Goal: move from phase-1 heuristics to durable multi-language architecture.

Scope:
- Decide long-term strategy:
  - Tree-sitter deeper integration per language, or
  - Hybrid tokenizer + parser strategy.
- Define packaging behavior when grammars/runtime are unavailable.
- Improve fallback UX and performance behavior for large files.

Acceptance criteria:
- Documented architecture decision with tradeoffs.
- Clear runtime capability detection and fallback behavior.
- Tests for at least the primary target language set.

## Phase 5: WYSIWYG Feasibility to Delivery Path (P2/P3)

Goal: establish practical route from hybrid editor to robust round-trip WYSIWYG.

Scope:
- Define canonical intermediate document model (AST + source mapping).
- Build deterministic Markdown serializer with minimal-destructive rewrite rules.
- Start with constrained editable subset (headings/lists/links/emphasis/code).
- Add round-trip correctness suite and corpus-based differential tests.
- Expand editable scope only after serializer reliability metrics are met.

Acceptance criteria:
- Round-trip suite demonstrates stable serialization for MVP subset.
- Formatting rewrites are bounded, intentional, and test-verified.
- Clear go/no-go gate for full-fidelity WYSIWYG continuation.

## Phase 6: Project Readiness and Governance (P1)

Goal: align legal/release posture with project direction.

Scope:
- Resolve license alignment decision and update headers/docs.
- Publish contributor-facing architecture and extension points.
- Define release checklist including compatibility matrix and migration notes.

Acceptance criteria:
- License issue closed with explicit rationale.
- Source headers and project docs match selected license policy.
- Release process documented and repeatable.

## Execution Order (Recommended)

1. Phase 0
2. Phase 1
3. Phase 2
4. Phase 3
5. Phase 6
6. Phase 4
7. Phase 5

Notes:
- Phase 6 can run in parallel after Phase 1 if legal/doc updates are not blocked on architecture decisions.
- Phase 5 should not begin full implementation until Phases 0-2 have removed core reliability risk.

## Suggested Next 2 Sprints

Sprint A:
- Complete large-document line-number/indexing optimization (Phase 2).
- Add measurable performance budget checks for preview render/apply/post stages.
- Add benchmark-oriented validation for split sync + large files.
- Start UI regression harness work for split/layout screenshots (Phase 3).

Sprint B:
- Finish UI regression harness and visual baseline capture flow.
- Close remaining phase-1 polish follow-up items (zoom slider visibility, toolbar alignment, preferences default decision).
- Add automated checks for split-pane hierarchy/layout regressions.
- Lock updated P1 performance/polish checklist for release readiness.

## Completion Criteria for "World-Class" Claim

- No known P0/P1 safety or responsiveness risks open.
- Reliable round-trip behavior for defined editing surface with objective test coverage.
- Stable UI behavior across supported themes/platforms.
- Performance budgets enforced by automated checks.
- Clear legal, release, and contributor governance.

# Milestone 11 - UI Polish Pass (Phase 1)

## Status Snapshot (2026-02-16 EOD)

Completed today:
- Split-pane rendering regression is resolved.
- Primary toolbar icon regression (`Open` / `Save`) is resolved.
- Top horizontal source ruler removal and line-number scrolling stability remain in place.

Next-up (resume tomorrow):
- Verify zoom slider thumb/track visibility across active GNUstep theme(s).
- Refine toolbar vertical alignment (mode + zoom controls) without adding toolbar height.
- Confirm whether `Preferences` should be part of the default toolbar layout.

## 1) Toolbar Hierarchy + Density

The toolbar should now emphasize primary actions.

Expected:
- Primary buttons: `Open`, `Save`
- Primary controls: `View` mode segmented control, preview state, zoom controls
- Lower-frequency actions (`Import`, `Export PDF`, `Print`) remain in menus

Quick check:
- Confirm toolbar feels less crowded than before.
- Confirm mode/zoom controls are still visible and usable.

## 2) Preview State Clarity

Expected status text labels:
- `Preview Live`
- `Preview Updating`
- `Preview Stale`
- `Preview Hidden`

Quick check:
- In `Split`, type in source and watch transitions between live/updating/stale.
- In `Edit` mode, verify state indicates hidden.

## 3) Split Sync Naming (Plain Language)

Use `View -> Split Sync` and verify options:
- `Independent`
- `Linked Scrolling`
- `Follow Caret`

Also verify same names in `ObjcMarkdownViewer -> Preferences...`.

## 4) Preferences Information Architecture

Preferences should now be grouped by sections:
- `Preview Sync`
- `Rendering`
- `Editing`

Expected:
- Section headers + separators improve scanability.
- Controls are easier to discover by task area.

## 5) Source/Preview Cohesion (Deferred)

Current decision:
- Keep renderer/theme default preview background for stability.
- Revisit background softening only after a safer implementation path is defined.

## 6) Editor Chrome Cleanup + Ruler Stability

Expected:
- Top horizontal ruler is removed in source editor.
- Vertical line numbers remain visible while scrolling deep into document.

Stress check:
- Scroll source pane far down and back up quickly.
- Line numbers should remain stable and not disappear near top.

## 7) Regression Notes

Keep validating from previous milestones:
- Link opening
- Remote image toggle behavior
- Ctrl/Cmd+Shift+Arrow selection behavior
- Source + renderer syntax highlighting toggles

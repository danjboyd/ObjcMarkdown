# Milestone 10 - Split Sync Modes + Toolbar Alignment

## 1) Split Pane Sync Modes

Use `View -> Split Pane Sync` (or `ObjcMarkdownViewer -> Preferences... -> Split Pane Sync`) and validate each mode:

- Unlinked
- Linked Scrolling
- Caret/Selection Follow

### A) Unlinked

1. Switch to `Split` mode.
2. Set `Split Pane Sync -> Unlinked`.
3. Scroll the left source pane.
4. Scroll the right preview pane.
5. Move caret and select text in either pane.

Expected:
- Panes do not auto-scroll each other.
- Selection/caret changes do not move the other pane.

### B) Linked Scrolling

1. Set `Split Pane Sync -> Linked Scrolling`.
2. Scroll in the source pane (mouse wheel/trackpad/scrollbar).
3. Scroll in the preview pane.

Expected:
- Scrolling either pane moves the other pane to corresponding content.
- Behavior is stable (no oscillation/jitter loops).

### C) Caret/Selection Follow

1. Set `Split Pane Sync -> Caret/Selection Follow`.
2. Move caret in source and select text.
3. Click/select text in preview.

Expected:
- Source caret/selection drives preview position.
- Preview selection drives source position.
- This is selection-based, not continuous scroll-linking.

## 2) Preferences Sync

Open `ObjcMarkdownViewer -> Preferences...` and verify:

- `Split Pane Sync` popup reflects the current View-menu mode.
- Changing popup value updates View-menu checkmarks immediately.

## 3) Toolbar Vertical Alignment

Check the toolbar row visually:

- Mode segmented control should look vertically centered and less cramped.
- Zoom slider should be vertically centered (not pinned to the top).

## 4) Stress Snippet

Use this section for quick scroll/link behavior checks:

Line 01
Line 02
Line 03
Line 04
Line 05
Line 06
Line 07
Line 08
Line 09
Line 10
Line 11
Line 12
Line 13
Line 14
Line 15
Line 16
Line 17
Line 18
Line 19
Line 20
Line 21
Line 22
Line 23
Line 24
Line 25
Line 26
Line 27
Line 28
Line 29
Line 30
Line 31
Line 32
Line 33
Line 34
Line 35
Line 36
Line 37
Line 38
Line 39
Line 40
Line 41
Line 42
Line 43
Line 44
Line 45
Line 46
Line 47
Line 48
Line 49
Line 50

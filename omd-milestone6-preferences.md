# Milestone 6 - Preferences Dialog + Input Shim Toggle

## 1) Preferences Dialog

Open `ObjcMarkdownViewer -> Preferences...` (or `Cmd+,`).

Expected controls:
- Math Rendering Policy
- Allow Remote Images
- Word Selection for Ctrl/Cmd+Shift+Arrow in Source Editor

## 2) Word-Selection Shim Toggle

In source editor, test on this line:

alpha beta gamma

### Expected when shim is ON

1. Put caret at end of `gamma`.
2. Press `Ctrl/Cmd+Shift+Left`.
3. Press `Ctrl/Cmd+Shift+Right`.

Behavior:
- Left selects `gamma` as a word.
- Right collapses back to no selection at original caret.

### Expected when shim is OFF

Behavior should follow host GNUstep keybinding behavior (may be char/line based).

## 3) Sync Check

Toggle setting in Preferences and confirm `View -> Word Selection for Ctrl/Cmd+Shift+Arrow` checkmark updates, and vice versa.

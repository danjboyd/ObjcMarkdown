# Milestone 5 - Toggle + Keyboard Fixes

## 1) Remote Image Toggle Should Apply Immediately

Use `View -> Math Rendering -> Allow Remote Images` on this section:

![Remote Markdown Icon](https://raw.githubusercontent.com/github/explore/main/topics/markdown/markdown.png)

Expected:
- Toggle ON: image may render.
- Toggle OFF: image should immediately disappear and revert to fallback text.

## 2) Ctrl+Shift+Arrow Word Selection (Source Pane)

In the left source editor:

1. Put cursor between words in this line: `alpha beta gamma`
2. Press `Ctrl+Shift+Left` repeatedly.
3. Press `Ctrl+Shift+Right` repeatedly.

Expected:
- Selection expands by word segments, not one character at a time.
- Behavior is deterministic in source editor.

alpha beta gamma

# Milestone 7 - Source Syntax Highlighting + Sync Hardening

## 1) Syntax Highlighting Baseline

Use `View -> Source Syntax Highlighting` and keep it ON.

In the source pane, this document should show distinct colors for:
- Headings (`# ...`)
- Lists (`- ...`)
- Links (`[label](url)`)
- Emphasis (`*italic*`, `**bold**`)
- Inline code (`` `code` ``)
- Fenced code blocks
- Math spans (`$...$` / `$$...$$`)

Example tokens:

- **bold**
- *italic*
- [Open AGENTS.md](AGENTS.md)
- Inline code: `printf("hello")`
- Inline math: $E = mc^2$

```objc
int main(void) {
  return 0;
}
```

## 2) Toggle Behavior

1. Turn `View -> Source Syntax Highlighting` OFF.
2. Source colors should reset to plain editor text color.
3. In `Split` mode, the right preview pane should remain visible (it should not disappear).
4. Turn it ON again and colors should return.

## 3) Preferences Sync

Open `ObjcMarkdownViewer -> Preferences...` and verify:
- `Source Syntax Highlighting` checkbox matches the View-menu checkmark.
- Toggling either control updates the other immediately.

## 4) Repeated-Block Mapping Sanity (Split Mode)

Switch to `Split` mode and test with this section:

repeat block

repeat block

Place cursor in the second `repeat block` line and type a few characters quickly.

Expected:
- Source typing remains stable.
- After debounce, preview catches up without jumping to the wrong repeated paragraph.

## 5) Renderer Code-Block Highlighting (Objective-C fences)

In the right preview pane, the Objective-C fenced code block in this file should show token color variation (for example, comment and keyword colors differing from plain identifiers).

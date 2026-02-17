# Milestone 8 - Tree-sitter Gated Renderer Syntax Highlighting

## 1) Renderer Syntax Highlighting Preference

Open `ObjcMarkdownViewer -> Preferences...` and verify:

- `Renderer Syntax Highlighting (Code Blocks)` checkbox is present.
- A note appears below it describing Tree-sitter dependency.
- On this machine, Tree-sitter should be detected and the checkbox should be enabled.

## 2) Toggle Behavior in Preview

Use `View -> Renderer Syntax Highlighting` and verify this section:

```objc
int main(void) {
  // note
  return 42;
}
```

Expected:

- Toggle ON: keywords/comments/numbers are colorized.
- Toggle OFF: code block returns to uniform text color.

## 3) Preference Persistence

- Leave toggle in your chosen state.
- Close and relaunch app on this same file.
- Confirm `View` menu checkmark and Preferences checkbox state persist.

## 4) Baseline Language Coverage (Current)

These fenced blocks should show first-pass token coloring when toggle is ON:

```python
def add(a, b):
    # comment
    return a + b
```

```javascript
const value = 42;
// comment
console.log(value);
```

```bash
NAME="world"
echo "hello ${NAME}"
```

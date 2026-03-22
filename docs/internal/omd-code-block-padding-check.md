# Code Block Padding Verification

Use this document to visually verify code block spacing, background fill, and `Copy` button placement.

Quick checks:
- Code text should have comfortable left/right breathing room.
- Top and bottom padding should not feel cramped.
- `Copy` buttons should not visually collide with top block content.

---

## 1) Fenced Block (Short)

```c
for (int i = 0; i < 3; i++) {
    puts("fenced");
}
```

## 2) Indented Code Block

    for (int i = 0; i < 3; i++) {
        puts("indented");
    }

## 3) Fenced Block (Long Lines)

```javascript
const veryLongValue = "This line is intentionally long so you can evaluate inner horizontal spacing, wrapping behavior, and right-side breathing room near the edge of the code block background.";
function renderPaddingDemo() {
  console.log("Observe left/right inset, top/bottom space, and copy button offset.");
}
```

## 4) Multiple Blocks Back-to-Back

```bash
echo "first block"
```

```python
def hello():
    print("second block")
```

```sql
SELECT id, title, created_at
FROM documents
WHERE title LIKE '%padding%'
ORDER BY created_at DESC;
```

## 5) Blockquote + Code Block

> Quoted context before code:
>
> ```toml
> [theme.code]
> background = "#F6F8FA"
> text = "#24292F"
> ```

## 6) List + Code Block

1. Verify spacing in nested contexts.

   ```sh
   ./build.sh --target viewer --profile debug
   ./run.sh --open omd-code-block-padding-check.md
   ```

2. Confirm alignment stays consistent between blocks.

## 7) Inline Code vs Block Contrast

Inline sample: `let padding = 20;` and `copyButtonYOffset = 5;`

```swift
let padding: CGFloat = 20
let copyButtonYOffset: CGFloat = 5
print("Code block should feel less dense than before.")
```

---

End of spacing fixture.

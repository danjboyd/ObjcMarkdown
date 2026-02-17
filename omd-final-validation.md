# ObjcMarkdown Final Validation (Repo-Local)

This version is located in the repository so relative links resolve to real files.

## 1. Relative Link Resolution

- [Open AGENTS.md](AGENTS.md)
- [Open renderer implementation](ObjcMarkdown/OMMarkdownRenderer.m)
- [Open open issues](OpenIssues.md)

Expected: each click opens the target file in your default app and does not beep.

## 2. Inline + Block HTML Policy (default render-as-text)

Inline HTML should appear literally: <span data-test="inline">inline html node</span>

<div class="note">
This block HTML should appear as literal text when policy is RenderAsText.
</div>

## 3. Images

![Toolbar Open Icon](Resources/toolbar-open.png)

Expected: rendered inline as an attachment image.

## 4. Math Policy Behavior

Inline math sample: $E = mc^2$

Display math sample:

$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$

Expected under default safe policy: styled text path (no external tool execution).

## 5. Split Mode Typing

Switch to `Split` mode and type rapidly in source pane below:

- Item one
- Item two
- Item three

Expected: no heavy cursor jitter/churn while preview is stale; preview catches up on debounce.

# Milestone 9 - Phase 1 Closeout Validation

This file validates the post-Phase-1 hardening short of full WYSIWYG.

## 1) Source Highlighting Accessibility + Preferences

Open `ObjcMarkdownViewer -> Preferences...` and verify:

- `Source Syntax Highlighting` toggle exists.
- `High Contrast Source Highlighting` exists and updates colors immediately.
- `Source Accent Color` color-well changes heading/link accent in source editor.
- `Reset` clears custom accent back to default behavior.

In `View` menu, verify quick toggle:

- `Source Highlight High Contrast`

## 2) Preview Sync Discoverability

In toolbar mode controls, verify status text changes:

- `Preview: live`
- `Preview: updating` (while debounce/render is pending)
- `Preview: stale` (in Split mode while source changes are ahead of last render)
- `Preview: hidden` (in Edit mode)

## 3) Renderer Fenced-Code Language Coverage

Toggle `View -> Renderer Syntax Highlighting` ON and inspect these blocks:

```yaml
name: objcmarkdown
count: 42
# yaml comment
```

```toml
[app]
name = "objcmarkdown"
enabled = true
```

```sql
SELECT id, name FROM users WHERE id = 42;
-- sql comment
```

```ruby
def greet(name)
  puts "hello #{name}"
end
```

```html
<div class="pane">hello</div>
```

## 4) Math Policy Transition + Stress Sanity

Use `View -> Math Rendering` and verify:

- `Styled Text (Safe)`: `$...$` is rendered styled.
- `Disabled (Literal $...$)`: literal `$...$` appears.
- Switching back to `Styled Text (Safe)` restores styled rendering.

Inline sample: $a^2+b^2=c^2$

Display sample:
$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$

## 5) Split Editing Stability (Large-file strategy)

In Split mode:

- Paste several copies of this file (or a large markdown doc).
- Type quickly in source pane.
- Verify typing remains stable and preview catches up after debounce.

Expected:

- No cursor churn/jitter regressions.
- Source highlighting remains responsive with adaptive/incremental behavior on larger docs.

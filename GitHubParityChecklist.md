# GitHub Rendering Parity Checklist (Code Blocks)

This checklist tracks visual parity against GitHub rendering for `omd-code-block-padding-check.md`.

## Comparison Baseline

- Source fixture: `omd-code-block-padding-check.md`
- GitHub reference: `https://github.com/danjboyd/ObjcMarkdown/blob/main/omd-code-block-padding-check.md`
- Local app: `ObjcMarkdownViewer` in `Split` mode, preview zoom near 100-125%

## Design Targets

1. Container shape:
- Rounded code block container with subtle border.
- Background close to GitHub `#F6F8FA`, border close to `#D0D7DE`.

2. Inner spacing:
- Horizontal code inset should feel clearly intentional, not cramped.
- Vertical breathing room should be visible for 2-3 line blocks.

3. Copy affordance:
- Control should be visually secondary to code content.
- Avoid heavy filled buttons that dominate block corners.

4. Nested context behavior:
- Code blocks inside blockquotes/lists should inherit visible nesting.
- Avoid full-width slabs that flatten hierarchy.

5. Typography:
- Block code should read slightly smaller/tighter than body copy.
- Syntax color contrast should remain legible.

6. Long-line behavior:
- Target GitHub behavior: horizontal scrolling within code blocks.
- Current `NSTextView` approach wraps long lines; this remains a known gap.

## Current Status (This Pass)

- Implemented:
- Rounded container drawing with border in preview and print.
- GitHub-adjacent background/border colors.
- Nested indentation preserved by drawing to code block glyph bounds.
- Block code no longer paints per-run background; container provides true inner padding.
- Copy control now uses a bundled icon asset (`Resources/code-copy-icon.png`) with text fallback.
- Copy button placement tracks code-block container padding and sits in the top-right corner without covering first-line code text.
- Block code font size reduced slightly and line-height tightened.

- Partially matched:
- Copy control interaction (GitHub typically reveals more contextually; ours remains always visible).

- Not yet matched:
- Per-block horizontal scrolling for long lines.

## Next Steps

1. Evaluate renderer architecture options for non-wrapping code block lines:
- dedicated code block views in preview, or
- layout manager customization for block-local no-wrap behavior.
2. Decide whether copy controls should stay always visible or switch to hover/focus reveal.
3. Re-run side-by-side capture and update this checklist with pass/fail notes.

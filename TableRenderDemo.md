# GFM Table Rendering Demo

This document is a focused fixture for validating GitHub-flavored table rendering.

## Basic Alignment Table

| Column | Left | Center | Right |
| :----- | :--- | :----: | ----: |
| A      | one  |  mid   |     1 |
| B      | two  |  mid   |   200 |
| C      | three|  mid   |  3456 |

## Markdown-in-Cell Table

| Feature | Example | Expected |
| :------ | :------ | :------- |
| Bold | **strong text** | Styled in editor source; readable in preview |
| Inline code | `printf("hello")` | Monospace inline style |
| Link | [ObjcMarkdown](https://github.com/) | Clickable link |
| Escaped pipe | literal \| separator | Single cell with a pipe character |

## Wider Content Table

| Area | Notes | Status |
| :--- | :---- | -----: |
| Parsing | Handles standard pipe table delimiter row and alignment markers. | 100 |
| Rendering | Output should stay column-aligned and legible on dark theme. | 95 |
| Edge cases | Escaped pipes should not split into extra cells. | 90 |

## Mixed File Test Instructions

1. Open this file in split mode.
2. Confirm each table appears structured in preview.
3. Compare source vs preview to verify row/column alignment.

# CommonMark Sample

This document exercises **CommonMark** features for rendering tests.

- Emphasis: *italic* and _italic_
- Strong: **bold** and __bold__
- Combined: ***bold italic*** and **_bold italic_**
- Inline code: `printf("hello")`
- Escapes: \*not italic\* and \_not italic\_
- Link: [CommonMark](https://commonmark.org)
- Autolink: <https://example.com>
- Image: ![Alt text](https://example.com/image.png)

---

## Paragraphs and Line Breaks

Soft line break example:
This is a single paragraph with
soft line breaks that should wrap.

Hard line break example (two spaces):
This line has two spaces at the end.  
This should break to a new line.

## Lists

### Unordered

- First item
- Second item
  - Nested item A
  - Nested item B
- Third item

### Ordered

1. First item
2. Second item
   1. Nested item 1
   2. Nested item 2
3. Third item

## Blockquote

> This is a blockquote.
> It can span multiple lines.
>
> - It can contain lists
> - and other inline elements like **bold**.

## Code Blocks

Indented code block:

    for (int i = 0; i < 3; i++) {
        puts("indented");
    }

Fenced code block:

```
function hello() {
  console.log("fenced");
}
```

## Inline HTML

<div>HTML is allowed in CommonMark.</div>

## Thematic Break

***

## Mixed Content

A paragraph with **bold**, *italic*, `code`, and a [link](https://example.com).


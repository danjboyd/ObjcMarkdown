# Mermaid `erDiagram` Rendering - Design And Phase Plan

- **Opened On**: 2026-09-01
- **Area**: Renderer / Preview fidelity / Diagram support
- **Tracking Issue**: `OpenIssues.md` issue 11

## Goal

Render fenced ` ```mermaid ` blocks that contain a Mermaid `erDiagram` as a real
entity-relationship drawing in the preview, instead of showing the diagram source
as a code block.

Non-goals for this initiative:

- general Mermaid support (`flowchart`, `sequenceDiagram`, `stateDiagram`, `gantt`, ...)
- editing diagrams from the preview surface
- byte-for-byte visual parity with the JavaScript Mermaid renderer

Any Mermaid diagram type that is not an `erDiagram` keeps today's behavior: it is
rendered as a normal fenced code block.

## Audit: What The Repo Already Provides

Three existing mechanisms determine the design. This work is mostly assembly of
patterns that are already in the tree.

### 1) Fence-token dispatch already exists

`OMPrimaryFenceToken` (`ObjcMarkdown/OMMarkdownRendererCode.m`) lowercases the first
token of a fence info string, and `OMRenderCodeBlock` already receives the
`cmark_node`. Detecting a `mermaid` fence needs no parser changes and no cmark
extension.

### 2) Vector block-as-attachment already exists

`OMPipeTableAttachmentCell` and `OMPipeTableAttachmentAttributedString` implement
a complete "block that draws itself" path:

- the cell computes `cellSize` from a measured layout
- `drawWithFrame:` draws with Bezier paths and attributed strings
- colors come from the theme and adapt to dark backgrounds via `OMThemeBackgroundIsDark`
- because drawing is vector, print and PDF export come out crisp
- there is an `NSImage` fallback if attachment-cell construction fails

This is the model the diagram renderer follows.

### 3) An optional-external-toolchain pipeline already exists (math)

The LaTeX math path provides the template for policy enums, `NSTask` execution,
artifact caching, async warm-up with a "did warm" notification, and a
`View` menu policy submenu backed by a `NSUserDefaults` key.

The diagram work reuses the *policy and menu* half of this pattern, but
deliberately not the external-process half. See the next section.

## Decision: Native Rendering, Not `mermaid-cli`

The obvious implementation is to shell out to `mmdc` (mermaid-cli). Rejected, for
three concrete reasons.

**Dependency weight.** `mmdc` requires Node plus Puppeteer plus a bundled
Chromium - roughly 150 MB of runtime that would have to be carried into both the
Linux AppImage and the Windows MSI. That is larger than the entire application and
works against the release gate described in `Roadmap.md`.

**SVG decoding is the weak link on this stack.** `gnustep-gui` ships no SVG image
rep; `[[NSImage alloc] initWithData:svgData]` in the math path resolves through
`GSImageMagickImageRep`. On the reference Linux box ImageMagick has no
`rsvg-convert` delegate installed, so SVG decoding falls back to ImageMagick's
internal MSVG renderer. That is adequate for `dvisvgm` output, which is plain path
data, but Mermaid's SVG uses CSS in `<style>` blocks, marker definitions, and
sometimes `foreignObject` - all of which MSVG renders incorrectly or not at all.
On Windows the math path already abandons SVG entirely and uses `dvipng` PNG
output, so a Mermaid SVG pipeline would need a second rasterization strategy there.

**Output quality.** A rasterized diagram loses on zoom and in PDF export. The
existing pipe-table cell wins on both because it re-draws as vectors at the
target resolution.

`erDiagram` is the tractable subset of Mermaid: boxes containing an attribute
grid, plus edges with crow's-foot endpoints. That is the pipe-table problem plus
graph layout. Implementing it natively gives crisp PDF output, live theme colors,
deterministic geometry (and therefore testable geometry), and no new runtime
dependency.

## Design

### New library unit

`ObjcMarkdown/OMMermaidERDiagram.{h,m}` for the model and parser, and
`ObjcMarkdown/OMMermaidERLayout.{h,m}` for the geometry, both kept out of
`OMMarkdownRenderer.m` so that file does not grow further. Four separable pieces:

1. **Model + parse.** `erDiagram` header, relationship lines
   (`CUSTOMER ||--o{ ORDER : places`), and attribute blocks
   (`uuid id PK`, `text email UK "unique"`). Parse failures return `nil` plus an
   `NSError` carrying a 1-based source line number.
2. **Layout.** Deterministic layered placement: rank entities by breadth-first
   traversal from the highest-degree entity, order within ranks by barycenter to
   reduce crossings, then route edges orthogonally with lane assignment.
   Determinism matters for golden-geometry tests and for scroll-sync stability
   across re-renders.
3. **Draw.** `OMMermaidDiagramAttachmentCell : NSTextAttachmentCell`, a sibling of
   `OMPipeTableAttachmentCell`. Colors come from `OMTheme` via a new optional
   `[diagram]` TOML section that defaults to the existing table border, header,
   and body colors, so both light and dark themes are correct on day one.
4. **Integrate.** In `OMRenderCodeBlock`, when the fence token is `mermaid`:
   parse; on success emit the attachment; on failure fall through to the existing
   code-block rendering plus a one-line diagnostic.

### Parsing options

Mirrors the math policy exactly:

```objc
typedef NS_ENUM(NSInteger, OMMarkdownDiagramRenderingPolicy) {
    OMMarkdownDiagramRenderingPolicyDisabled = 0,   // treat as plain code block
    OMMarkdownDiagramRenderingPolicySourceCode = 1, // highlighted code block
    OMMarkdownDiagramRenderingPolicyNative = 2      // draw the diagram
};
```

Default is `Native`. Because rendering is in-process with no external toolchain,
there is no availability gate to check at startup.

### Viewer wiring

Five touch points, each with an existing math analogue in `OMDAppDelegate.m`:

- a `View -> Diagram Rendering` submenu next to `Math Rendering`, plus the
  defaults key, the preferences popup, and the `validateMenuItem` case
- a new `diagramRanges` array on the renderer, kept **out of** `codeBlockRanges`.
  `OMDTextView` paints a code-block background over every range in
  `codeBlockRanges`, which would draw a filled panel behind the diagram
- the copy-button layout pass consumes `diagramRanges` as well, with a
  "Copy diagram source" tooltip, so copying the Mermaid source still works
- the print/export renderer needs the same range hand-off as the on-screen one
- `OMRecordBlockAnchor` already fires for code-block nodes, so split-view scroll
  sync needs no change

### Sizing

Diagrams honor `layoutWidth` and `zoomScale` like other blocks. Wide diagrams
scale to fit down to a legibility floor, then overflow, consistent with the
current wide-table behavior. Reuse the fit-to-width logic in
`OMPreparedImageForAttachment`.

## Phase Plan

| Phase | Scope | Rough size |
|---|---|---|
| 1 | Model, parser, parser tests, fence dispatch, code-block fallback | ~600 lines + tests |
| 2 | Layout engine + golden-geometry tests | ~700 lines |
| 3 | Attachment-cell drawing, theme colors, zoom/width/PDF behavior | ~600 lines |
| 4 | Viewer menu, preferences, copy button, sample document, README/Roadmap updates | ~250 lines |

Phase 2 is the only genuinely novel work. The rest is pattern-matching against
code already in the tree.

## Supported `erDiagram` Subset

Phase 1 parses:

- the `erDiagram` header line, with optional leading/trailing whitespace
- `%%` comment lines
- relationship lines: `LEFT <cardinality> RIGHT : label`, where the label may be
  bare or double-quoted, and may be empty (`: ""`)
- cardinality tokens in both directions, with optional-identifying variants:
  `|o`, `||`, `}o`, `}|` on the left; `o|`, `||`, `o{`, `|{` on the right;
  joined by `--` (identifying) or `..` (non-identifying)
- entity attribute blocks: `ENTITY { ... }`, one attribute per line, of the form
  `type name [PK|FK|UK ...] ["comment"]`
- entity aliases (`CUSTOMER["Customer Record"]`) are accepted and the alias is
  used as the display name

Anything else in the block is a parse failure, and a parse failure means the
block renders as ordinary code. Known statements outside the subset include
`direction`, YAML frontmatter, and `%%{init: ...}%%` directives. Fallback is the
rule: an unsupported or malformed diagram must never hang, crash, or produce a
half-drawn figure.

## Phase 1 Outcome (2026-09-01)

Landed:

- `ObjcMarkdown/OMMermaidERDiagram.{h,m}`: `OMMermaidERDiagram`,
  `OMMermaidEREntity`, `OMMermaidERAttribute`, `OMMermaidERRelationship`, and a
  strict recursive-descent-style line parser over the subset above.
- `+sourceDeclaresERDiagram:` as the cheap gate, so the parser never runs over
  `flowchart`, `sequenceDiagram`, or any other mermaid diagram type.
- Fence dispatch in `OMRenderCodeBlock`, with the code block retained as the
  rendering result for every case.
- 30 parser tests in `ObjcMarkdownTests/OMMermaidERDiagramTests.m` and 4 renderer
  tests in `OMMarkdownRendererTests.m`.

One behavior was added beyond the original phase sketch. When a mermaid block
declares `erDiagram` but does not parse, the renderer appends a muted italic
diagnostic line beneath the code block, naming the failing line - for example
`mermaid erDiagram, line 4: Attribute needs a type and a name.` Parser errors
carry a line number relative to the diagram source, and the renderer shifts it
onto the enclosing document using the code block's cmark start line, so the
number points at a line the reader can navigate to. Mermaid blocks of other
diagram types stay silent, because rendering those as code is correct rather
than a failure.

The diagnostic is deliberately appended outside the recorded code-block range,
so `OMDTextView` does not paint the code background behind it and the copy
button geometry is unaffected. A renderer test asserts that separation.

## Risks

- **Layout quality.** Crossing-heavy schemas may look worse than Mermaid's own
  output. Mitigation: cap entity and relationship counts, and fall back to the
  code block above the cap rather than drawing something unreadable.
- **`NSTextAttachmentCell` behavior on GNUstep.** The pipe-table cell proves the
  path works, and it carries an `NSImage` fallback that can be copied.
- **Valid-but-unsupported Mermaid.** Source that is legal Mermaid yet outside the
  parsed subset must fall back quietly, which is why the parser is strict and
  returns errors rather than guessing.

## Phase 2 Outcome (2026-09-01)

Landed in `ObjcMarkdown/OMMermaidERLayout.{h,m}`:

- `OMMermaidERLayoutMetrics`, a value object holding every spacing constant, so
  the renderer can derive geometry from theme fonts later without touching the
  algorithm.
- `OMMermaidERTextMeasuring`, a protocol supplying title, attribute, and label
  widths. Layout never touches `NSFont`, which is what makes the geometry tests
  exact rather than machine dependent. The renderer will implement it against
  the theme in Phase 3; tests implement a fixed-width stub.
- `OMMermaidERDiagramLayout`, producing `OMMermaidEREntityLayout` (box, title
  band, and per-attribute column rects), `OMMermaidEREdgeLayout` (orthogonal
  polyline plus label rect), and an overall size, all in a top-left origin,
  y-down coordinate space.
- 23 tests in `ObjcMarkdownTests/OMMermaidERLayoutTests.m`: two exact golden
  geometry cases, plus invariants (no overlap within a rank, ranks strictly
  ordered vertically, polylines orthogonal, endpoints on their own box edges,
  everything inside the reported size) and a determinism check.

The pipeline, in order: size the boxes; rank by breadth-first distance from the
busiest entity of each component; reorder within ranks by barycenter over four
alternating sweeps; place horizontally and centre each rank; assign every edge to
the gap it crosses and to a lane within that gap; size the gaps to fit their
lanes and set rank offsets; distribute attachment points along each box edge;
then route and place labels.

Two decisions worth recording:

- Disconnected components share the rank rows rather than stacking, so a diagram
  with two independent clusters lays them out side by side.
- Attachment points are distributed across a box edge and ordered by where the
  far end sits. That alone separates parallel relationships between the same two
  entities: each gets its own pair of attachment points, and when those line up
  vertically the edge routes as a single straight segment.

Known limitations to revisit if real documents need them:

- An edge spanning more than one rank runs vertically through the intervening
  ranks and can cross a box. Adding virtual nodes for skipped ranks is the
  standard fix, deferred until a real document needs it.
- Ranks are packed and centred, not aligned to their neighbours, so a wide rank
  next to a narrow one can look loose.

## Phase 3 Outcome (2026-09-01)

Landed in `ObjcMarkdown/OMMermaidERDrawing.{h,m}`:

- `OMMermaidERDrawingStyle`, the fonts and colors a diagram draws with, and
  `OMMermaidERStyleMeasurer`, which implements `OMMermaidERTextMeasuring` against
  those fonts so layout geometry and drawing agree.
- `OMMermaidERMetricsForStyle`, deriving every layout spacing constant from the
  style's font line heights, so a diagram scales with the document's zoom.
- `OMMermaidERDiagramAttachmentCell`, a sibling of `OMPipeTableAttachmentCell`.
  It reports `cellSize` from the layout and draws with Bezier paths and text, so
  print and PDF export come out at device resolution rather than rasterised.
- `OMMermaidERAttachmentAttributedString`, which lays the diagram out, picks a
  draw scale, and returns the one-character attachment string.

Renderer integration in `OMRenderCodeBlock`: a `mermaid` fence whose source
declares an `erDiagram` is parsed and drawn as an attachment. Everything else
falls back to the code block -- other diagram types silently, malformed source
with the line-numbered diagnostic from Phase 1, and a diagram past the layout
limits with a `too large to draw` explanation naming the counts.

Drawing details worth recording:

- Edges are drawn before boxes, so an edge routed under a box is hidden by it
  rather than crossing through the attribute rows.
- Cardinality markers are drawn from the polyline endpoints, oriented along the
  first and last segments: a crow's foot for the many variants, one bar for
  one-or-more, two bars for exactly-one, and a circle for the optional variants.
  The marker zone is clamped to 80% of the segment so short edges stay legible.
- Non-identifying relationships (`..`) stroke dashed; identifying ones solid.
- Relationship labels paint the body background behind themselves so the edge
  does not run through the text.
- A diagram wider than the text column shrinks by a uniform draw scale down to a
  floor of 0.55, past which it overflows instead, matching how wide tables behave.

Deviation from the plan: colors come from the existing pipe-table palette helpers
(`OMPipeTableBorderColorForTheme` and friends) plus the theme's text and link
colors, rather than a new `[diagram]` TOML section. That gives correct light and
dark rendering today with no new theme surface; a TOML section can be added in
Phase 4 if a theme needs to override the diagram palette specifically.

Tests: six renderer tests covering the attachment being produced, the drawn
diagram staying out of `codeBlockRanges`, the layout being reachable from the
cell, shrink-to-fit at a narrow width, growth with document zoom, and drawing
into an image context without raising. The existing fallback tests were kept and
extended to assert that no attachment is produced on the fallback paths.

## Phase 4 Outcome (2026-09-01)

Library:

- `OMMarkdownDiagramRenderingPolicy` on `OMMarkdownParsingOptions`, defaulting to
  `Native`.
- `-[OMMarkdownRenderer diagramBlocks]`, one dictionary per drawn diagram holding
  its range in the rendered string and the mermaid source it came from, keyed by
  `OMMarkdownRendererDiagramRangeKey` and `OMMarkdownRendererDiagramSourceKey`.
  Diagrams stay out of `codeBlockRanges` so no code background is painted behind
  them.

Viewer:

- `View -> Diagram Rendering` submenu with `Drawn Diagrams` and `Diagram Source`,
  plus the matching `validateMenuItem` check marks.
- A `Diagrams` row in Preferences, kept in sync with the menu through
  `syncPreferencesPanelFromSettings`, backed by the
  `ObjcMarkdownDiagramRenderingPolicy` default and read at startup.
- `updateCodeBlockButtons` now places copy buttons for both code blocks and
  diagrams. The placement loop was extracted into
  `-addCopyButtonsForRanges:action:toolTip:layoutManager:container:textOrigin:blockPadding:`
  and is called twice: once for code, once for diagrams with a
  `Copy diagram source` tooltip, zero padding, and the `copyDiagramBlock:`
  action, which copies the mermaid source rather than the attachment character.

Docs and samples: `Resources/sample-mermaid-er.md` exercises the drawn path, the
notation table, and both fallback paths; `README.md` and `Roadmap.md` mention
diagram support.

Deviation from the plan: the policy enum has two cases, not three. `Disabled` and
`SourceCode` would both have meant "render the fenced block as code", so the
third case was dropped rather than shipped as a duplicate. In `SourceCode` mode
the renderer also stays silent about malformed diagrams, since a reader who asked
for source is not asking for diagnostics.

The print and export path needed no change: it builds its own renderer and text
view, and diagrams draw through the same attachment cell, as vectors, at print
resolution.

## Validation

- Full suite green: 12 suites, 184 tests.
- Verified in the running app under Xvfb against `Resources/sample-mermaid-er.md`:
  the diagram draws in the preview with its copy button, and with the
  `ObjcMarkdownDiagramRenderingPolicy` default set to `0` the same document
  renders the fenced source as a code block instead.


# Editing from the Read view: design note

Status: draft, 2026-10-23. Tracking issues: #293 (Reveal in Source, 0.2.6) and
#294 (Edit Block, 0.2.7), both part of #63 (narrowed from "a full
WYSIWYG editor" to the constrained editing below).

Read is where people spend their time with a document, and the edits they
want there are small: a typo, a sentence, a heading. Today that means
switching to Split and finding the line. This note proposes two features
that let them make those edits from Read without the app ever rewriting
their Markdown.

## Goals

- Small edits without leaving the place you were reading.
- One rule the user can predict: what can be edited, and how, is the same
  for every part of the document. No text that is editable in one sentence
  and not in the next.
- The Markdown file stays the user's: every change is a minimal edit of the
  source text, in the user's own style, which undo reverts.
- Follow the UI rules in AGENTS.md: standard controls, system colours, no
  theme detection, nothing in Preferences.

Not goals: a WYSIWYG editor that turns edited rich text back into Markdown;
moving blocks, drag and drop, pasting rich text into Read; editing in the
macOS Quick Look preview.

## Why not editable rendered text

The obvious design lets the user type into the rendered text and maps each
keystroke back to the source. It can only work where a run of rendered
text is a literal copy of a run of source: not inside a link's
destination, a reference link, an entity (`&amp;`), an escape, inline HTML,
a table's pipes, math or a diagram. So typing would work in one sentence and
beep in the next, for reasons the user can't see. The user who finds that
the first paragraph is editable expects the whole document to be, and the
first refusal teaches them not to trust any of it. A partial editor is worse
than none.

The task box toggle (#285) is not that problem: a checkbox reads as a
control, and GitHub's read-only view toggles them too.

## What the user sees

### 1. Reveal in Source (any block)

Today a double-click on a rendered object (an image, a diagram, a formula)
switches Read to Split and selects the object's source
(`-textView:revealSourceOfRenderedObject:`). This generalises it to every
block:

- **Edit > Reveal in Source** and the same item in the preview's context
  menu, for the block under the click or the selection: switches to Split
  and selects the block's source (the selected text's source, when the
  mapping is exact).
- Rendered objects keep the double-click.
- It never refuses: every block has a source range.
- The name is the one the image, diagram and table menus already use, so
  the app has one name for one action.

Unlike today, the switch to Split is for this document only, not a new
preferred mode (`persistPreference:NO`): a user who prefers Read shouldn't
find every next document opening in Split.

### 2. Edit a block in place

- **Edit > Edit Block** (and in the context menu) opens the block under the
  click or the selection: a paragraph, heading, list item, block quote
  paragraph, table, code block, formula or diagram.
- The opened block is replaced, in the same text view and at the same
  place, by its Markdown source, styled as the source editor styles it. The
  rest of the document stays rendered. The caret goes where the user
  clicked when the mapping is exact, else to the start of the block.
- The user edits Markdown. Because it is source, nothing is out of bounds:
  links, entities and HTML all edit the same way.
- **Esc**, a click outside the block, or Command-Return closes it: the
  edit is kept and the block renders again. Undo reverts it; there is no
  separate cancel that could lose typing.
- Only one block is open at a time. Opening another closes the first.
- A read-only document (a remote README, a file the user can't write)
  disables both items, with the reason in the item's tooltip.

The trade-off is plain: while a block is open the user sees Markdown
syntax, not pure WYSIWYG. For people who chose a Markdown app that is
honest rather than a defect, and it is the pattern Typora and Obsidian's
live preview taught.

### Discoverability

- The menu items are where editing commands are found: the Edit menu and
  the context menu.
- The arrow cursor stays until a block is open, so nothing looks editable
  until it is. The open block has the I-beam and a caret.
- When the user types a printable key in Read with no block open, a
  transient notice (tooltip colours, as the other notices) says "Edit >
  Edit Block, or Command-Return, edits the block here", at most once per
  launch. No beep, no tour, no setting.

### Double-click

A double-click on text selects a word, which people use to copy while they
read. Taking it for Edit Block would trade that for a mode switch and a
reflow (the source is longer than its rendering) on every accidental
double-click. Recommendation: keep the double-click as word selection, and
open a block with **Command-Return** (no clash in the current menus; Use
Selection for Find has Command-E) or the menu items. Decision for Dan
below.

## How it works

The source text (the source editor's text storage) stays the only model.
The open block is a view of a range of it, not a copy.

- **Block ranges.** The renderer already records `blockAnchors` and each
  rendered object's `sourceRange`. It also records, for each leaf block,
  its range in the rendered string and its source character range, under
  a new key, the same way `-taskItems` records each box. They hold only
  while the preview matches the source (`_sourceRevision ==
  _lastRenderedSourceRevision`); otherwise the item is disabled until the
  render catches up.
- **Opening.** Replace the block's rendered range in the preview's text
  storage with the source substring, attributed by the source highlighter,
  and mark it with an attribute (`OMDOpenBlockAttributeName`). The preview
  becomes editable only inside that range
  (`-shouldChangeTextInRange:replacementString:` refuses any range outside
  it).
- **Editing.** Each change in the open block is applied to the same range
  of the source text storage, through the source view's undo manager, so
  Split (if shown) updates as the user types, the document is marked
  edited, and Save, autosave and recovery work as for any edit. The
  preview isn't re-rendered while the block is open.
- **Closing.** Re-render, then restore the scroll position so the block
  stays where it was. A later step can re-render only the block; the
  first version re-renders the document, debounced, as Split does today.
- **Elsewhere.** Quick Look's `OMDTextView` never opens a block. Vim mode
  (TextViewVimKit) applies in the open block as in the source editor.

## Invariants and tests

- **Minimal edits.** For each edit in an open block, the source changes
  only inside the block's source range; everything else is
  byte-identical. A property test over the renderer's test corpus: open
  every block, type, delete, close, and diff.
- **Round trip with no change.** Opening and closing a block without typing
  leaves the source byte-identical and the preview the same as before
  (line endings included: some files mix CRLF and LF).
- **Undo.** Each edit is one undo step, named as in the editor ("Undo
  Typing"), and undo after closing restores both the source and the
  preview.
- **Stale mapping.** With an unfinished render, the items are disabled and
  nothing opens.
- **OMDTextView tests** for the editable range, the cursor and the notice.

## Hazards to spike first

- GNUstep's text system: an editable sub-range of a non-editable text view,
  the caret and selection drawn in it, and the field editor not taking
  over. This is the spike's main question; if it can't be done cleanly,
  stop at feature 1.
- Focus: after a click in Split's preview, keyboard focus stays in the
  preview (the open #285 follow-up). With an editable preview the user will
  see it, so settle it first.
- Large documents: a long table or a 500-line code block opened in place;
  re-rendering a 1.4 MB document on close (still slow on Linux, #155).
- Input methods: a composition must commit into the open range.
- Accessibility: the open block must read as editable text.
- Both themes: the GNUstep theme and Adwaita, and the WinUITheme MSI and
  macOS.

## Plan

1. **Reveal in Source** for every block, with `persistPreference:NO` and the
   menu items. Small; no new risk.
2. **Spike** the open block on GNUstep, paragraphs only, with the minimal
   edit test. Go or stop on the hazards above.
3. **Edit Block** for every block type, the notice, the tests, by-eye
   checks under both themes and on Windows and macOS.

## Decisions for Dan

1. Double-click on text: keep word selection and open blocks with
   Command-Return and the menus (recommended), or open the block on a
   double-click.
2. Esc keeps the edit (recommended: undo reverts it) or cancels it.

## Releases

Dan, 2026-10-23: Reveal in Source (plan step 1) in 0.2.6, Edit Block (steps
2 and 3) in 0.2.7. Edit Block ships only if the spike says go; otherwise
0.2.7 goes without it.

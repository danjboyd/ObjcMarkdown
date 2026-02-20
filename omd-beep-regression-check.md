# Beep Regression Check

## A) Source Font Selector

1. Go to `View -> Source Editor Font -> Choose Monospace Font...`
2. Pick a different font and size.
3. Click apply/OK in the font panel.

Expected:
- No error beep.
- Source pane font updates.

## B) Dirty Close Prompt

1. Type in the left source pane so the document becomes dirty (`*` in title).
2. Close the window.
3. In the save prompt, test `Don't Save` and `Cancel` on separate attempts.

Expected:
- No error beep for either button.
- `Don't Save` closes the window.
- `Cancel` keeps the window open.

## C) Sanity

- Relative links still open.
- Split typing remains stable.

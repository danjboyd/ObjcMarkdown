# Edit Block (#294): on-screen checks

The checks the spike can't make headless. Run them on a scratch build of
`spike-294-edit-block`, only with Dan's screen go. Record the platform,
the theme and the build's commit, and give each check PASS, FAIL or SKIP
with a screenshot for each FAIL.

- **macOS:** a scratch copy of the app. Sparkle checks are off on it.
  Dan's prefs are exported before and imported after, and the two are
  diffed.
- **Linux:** the private display from `tools/dev/`, once under GNUstep's
  default theme and once under Adwaita.
- **Windows:** an OracleTestVMs lease, under WinUITheme. A dev build is
  fine here, since this isn't a release check.

## Document

Save this as `edit-block.md` and open it in Read mode, then repeat the
checks in Split mode with the preview focused.

```markdown
# Edit Block

A plain paragraph with *emphasis*, `code`, a [link](http://example.com "t")
and &amp; an entity.

> A quoted paragraph
> on two lines.

- Item text
  goes on.

Unicode: café, 日本語, an emoji 😀.
```

## Checks

1. **Open.** Click inside "emphasis", then choose Edit > Edit Block, and
   once more with its shortcut (Command-Return on macOS; on Linux and
   Windows, the key the menu shows). The paragraph shows its Markdown in the source
   font, and the caret is inside `*emphasis*`, not at the start of the
   paragraph.
2. **Type.** Type a word. It appears at the caret. Under Split, the source
   pane shows it at the same place, and nothing else in the source moves.
   The window shows the document as edited.
3. **Caret and selection.** Move with the arrow keys, then Home/End
   (Command-Left/Right on macOS), and select with Shift. The caret is drawn
   in the theme's colour and the selection in `selectedTextBackgroundColor`.
   Neither leaves the block.
4. **Outside the block.** Click into the next paragraph, or try to type
   with the selection reaching past the block. The click closes the block
   and renders it again, and no character lands outside the block.
5. **Close.** Press Esc, or the Edit Block shortcut again. The paragraph renders
   with the edit, and the scroll position doesn't jump.
6. **Undo.** Choose Edit > Undo once. The whole opening's typing goes
   back in one step, and the next undo is whatever came before. Redo puts
   the typing back.
7. **Quote and list.** Open the quoted paragraph. It shows "A quoted
   paragraph" and "on two lines." with no `>` on the second line. Press
   Return and type. In the source the new line starts with `> `. Do the same
   in the list item: there the new line starts with two spaces.
8. **IME.** Type an accented letter with dead keys (macOS: Option-E, then e)
   and a word through a CJK input method. The marked text shows inside the
   block, and the committed text reaches the source once, not twice.
9. **Unicode.** In the Unicode paragraph, place the caret after the emoji
   and delete backward. The emoji goes as one character, and the source
   holds no half surrogate pair.
10. **Accessibility.** With VoiceOver (macOS) or Orca (Linux), the open
    block's text is read and the caret moves are announced. Note anything
    missing here; it isn't a stop on its own.
11. **Themes (Linux).** Repeat 1 to 5 under GNUstep's default theme and
    under Adwaita. The text colour and the caret are readable in both, and
    the block's background matches the preview's.
12. **Dark (macOS, Windows).** Repeat 1 and 5 in dark appearance. The
    source text is drawn in `textColor`, readable on the dark page.

## Open questions for Dan

These are recorded, not decided by the checks:

- **Double-click.** Should a double-click open a block? It currently
  selects a word.
- **Esc.** Should Esc keep the edit (the current behaviour) or discard it?

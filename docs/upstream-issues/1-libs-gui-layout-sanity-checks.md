# libs-gui: -[GSLayoutManager _sanityChecks] makes every edit cost time proportional to the whole text

**Repository:** gnustep/libs-gui
**Reproducer:** [1-libs-gui-layout-sanity-checks.m](1-libs-gui-layout-sanity-checks.m)
**Status:** approved 2026-10-08 (see `docs/UPSTREAM_SIGNOFF.md`; draft `1511c05`, reproducer `042d1c0`).
**Filed:** https://github.com/gnustep/libs-gui/issues/992 (2026-10-08). The body is the text between the rules below, with the reproducer inline in a collapsed block before the disclosure line.

Everything between the two rules below is the issue as it would be filed:
the first line is its title, the rest its body.

---

GSLayoutManager: -_sanityChecks walks every glyph run on each glyph invalidation, so edits to a long text are quadratic

`-[GSLayoutManager _sanityChecks]` (Source/GSLayoutManager.m) walks the
whole glyph run list to check each run's `prev` link:

```objc
- (void) _sanityChecks
{
  glyph_run_t *g;

  g = (glyph_run_t *)&glyphs[SKIP_LIST_DEPTH - 1];
  while (g->head.next)
    {
      NSAssert((glyph_run_t *)((glyph_run_t *)g->head.next)->prev == g,
               @"glyph structure corrupted: g->next->prev!=g");
      g = (glyph_run_t *)g->head.next;
    }
}
```

It is called unconditionally in release builds, from three places:

- at the end of `-_generateRunsToCharacter:`;
- at the start and at the end of `-invalidateGlyphsForCharacterRange:changeInLength:actualCharacterRange:`.

So every edit to a text storage with a layout manager attached walks every
glyph run twice, whatever the size of the edit. Each run is an attribute
run, so a long, richly formatted text has many of them, and making N edits
to it costs O(N × runs). The walk stays even when assertions are compiled
out: only the `NSAssert` goes, not the loop.

**How to reproduce**

The attached reproducer builds a text of N lines whose fonts alternate
between two (so each line is its own run, with only two distinct attribute
dictionaries), lays it out in a 600 pt wide text container, then sets each
line's attributes again, one line at a time, to the ones it already has.
Nothing visible changes, but each call invalidates that line's glyphs. It
prints the time for the layout and for the edits as N doubles.

```
cc `gnustep-config --objc-flags` 1-libs-gui-layout-sanity-checks.m \
  `gnustep-config --gui-libs` -o layout-repro
./layout-repro
```

Results on Windows 11 (MSYS2 CLANG64, gnustep-base 1.31.1, gnustep-back
0.32 with the win32 server and cairo). "ratio" is the time divided by the time for half as many lines:

gnustep-gui 0.32.0 (the release, MSYS2 package `mingw-w64-clang-x86_64-gnustep-gui 0.32.0-3`):

| lines | chars | layout s | ratio | edits s | ratio |
|---:|---:|---:|---:|---:|---:|
| 1000 | 57890 | 0.027 | | 0.022 | |
| 2000 | 116890 | 0.075 | 2.8x | 0.103 | 4.7x |
| 4000 | 234890 | 0.237 | 3.2x | 0.376 | 3.7x |
| 8000 | 470890 | 0.564 | 2.4x | 1.481 | 3.9x |
| 16000 | 948890 | 2.500 | 4.4x | 8.088 | 5.5x |

master at 549f63913 (built with the same toolchain against the same
gnustep-base):

| lines | chars | layout s | ratio | edits s | ratio |
|---:|---:|---:|---:|---:|---:|
| 1000 | 57890 | 0.037 | | 0.043 | |
| 2000 | 116890 | 0.114 | 3.1x | 0.116 | 2.7x |
| 4000 | 234890 | 0.262 | 2.3x | 0.405 | 3.5x |
| 8000 | 470890 | 0.682 | 2.6x | 1.509 | 3.7x |
| 16000 | 948890 | 2.018 | 3.0x | 6.761 | 4.5x |

The edits take about four times as long each time the text doubles.

The same master with the body of `-_sanityChecks` compiled out:

| lines | chars | layout s | ratio | edits s | ratio |
|---:|---:|---:|---:|---:|---:|
| 1000 | 57890 | 0.031 | | 0.014 | |
| 2000 | 116890 | 0.064 | 2.1x | 0.029 | 2.1x |
| 4000 | 234890 | 0.139 | 2.2x | 0.054 | 1.9x |
| 8000 | 470890 | 0.285 | 2.1x | 0.087 | 1.6x |
| 16000 | 948890 | 0.744 | 2.6x | 0.191 | 2.2x |

The 16000 edits take 0.19 s instead of 6.8 s, and grow roughly linearly.
Layout gets faster too (0.74 s instead of 2.0 s at 16000 lines) but still
grows faster than the text, so something else in layout is superlinear.
That isn't covered here.

This was found in MarkdownViewer (danjboyd/ObjcMarkdown#94), where a
1.3 MB Markdown document kept a core busy for over a minute after
opening.

**Suggested fix**

Compile the walk only into debug builds, for example:

```objc
- (void) _sanityChecks
{
#ifdef GSLAYOUTMANAGER_SANITY_CHECKS
  ...
#endif
}
```

If there is an existing switch you would rather tie it to (`DEBUG`,
`GS_DEBUG`, or a debug default checked once), I'm happy to use that
instead. I can send this as a pull request.

Investigated, reproduced and written up with AI assistance (Claude).

---

## Not part of the issue: review notes

**What has been run for this draft (2026-10-08, the Windows dev box):**

- The reproducer above, built with clang and `-Wall` (no warnings), against:
  - the installed release, gnustep-gui 0.32.0 (MSYS2 `0.32.0-3`);
  - libs-gui master at 549f63913, built in a worktree;
  - that master with `packaging/patches/libs-gui/0001-...patch` applied.

  Each build was checked to be the `gnustep-gui-0.dll` the process loaded
  (from its module list). The tables are those runs' output.
- The call sites and the walk were read from master at 549f63913.
- Checked that it isn't already reported: searches of gnustep/libs-gui
  issues and pull requests (open and closed) for `_sanityChecks`,
  "sanityChecks", "GSLayoutManager slow", "layout quadratic",
  "glyph generation slow", "NSLayoutManager performance", "slow layout"
  found nothing related; no open pull request touches GSLayoutManager.
  The calls have been in the file since at least 2003 (bdc337317,
  74704f51e are the commits that changed them).

**Not done yet (needed before sign-off):**

- The GCC check on the reproducer
  (`tools/upstream/gcc-syntax-check.sh --files docs/upstream-issues/1-libs-gui-layout-sanity-checks.m`).
  This box's MSYS2 has no GCC Objective-C front end; run it on Linux.
- Not reproduced on Linux for this draft. The report says Windows only.
- The numbers from the earlier investigation in #94 (125 s to 0.5 s for
  laying out MarkdownViewer's 1.3 MB document) are left out: they come
  from another session's notes, not from a run for this draft.

**Choices to look at:**

- It's written as an issue with a suggested fix, not a pull request. A
  pull request would need a test in libs-gui's `Tests/`, and a timing test
  is hard to make reliable. A pull request could add a functional test
  instead (editing a laid-out text still gives the right glyphs), which
  shows the change breaks nothing but doesn't show the speed-up.
- It says "I'm happy to use that instead" and "I can send this as a pull
  request" in your voice. Those are offers, not claims that you checked
  something; change them if you'd rather not offer.
- The patch removes the walk from release builds only by a new macro;
  maintainers may prefer an existing one (the suggested-fix paragraph asks).

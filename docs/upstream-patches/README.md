# Patches prepared for upstream

Series prepared under [../UPSTREAM_POLICY.md](../UPSTREAM_POLICY.md) stage 1
go here, one directory per repository (`git format-patch` output), with a
line per series below: what it is, its test counts, its review state.

| Series | Patches | Tests | State |
|---|---|---|---|
| libs-back: dragging files out (XDND), `~/git/gnustep/libs-back-xdnd` on master `36ac709` | `libs-back/0001-...` (`5bcfb0b`), `0002-...` (`7be8987`) | xdndfilenames 9/9 (7 fail on master); xdndversion 7/7 (5 fail before); suite 300 passed, 0 failed (master 286 + 7 failed) | prepared 2026-10-16 ([review](review/libs-back-xdnd.md)); Dan chose to carry them in the Linux packages first (`packaging/patches/libs-back/0007`, `0008`) and live with them before review and sending |
| libs-back: copied files on the clipboard (xpbs), `~/git/gnustep/libs-back-clipfiles` on master `36ac709` | `libs-back/0003-...` (`c5c9fad`) | xpbscopiedfiles 9/9 (the file checks fail with an unpatched gpbs); suite 264 passed, 22 failed, the same 22 failures as master (255 passed) in the same environment, from tests run against the installed backend | prepared 2026-10-16 ([review](review/libs-back-xpbs-copied-files.md)); carried in the Linux packages first (`packaging/patches/libs-back/0009`) |
| libs-gui: tracking rect tags, `~/git/gnustep/libs-gui-trackingtag` on master `1dd8b76c6` | `libs-gui/0001-...` (`d7e5f5f`) | trackingRectTags 5/5 (1 fails without the change); gui tests by directory with a 90 s limit: the only difference from master is that check (`NSDatePicker` times out and 18 directories report failures on both) | approved by Dan 2026-11-06 ([sign-off](../UPSTREAM_SIGNOFF.md)); applies to master `8ac9f1db1` without a rebase |

The patches the Linux packages carry are in `packaging/patches/`; they
aren't prepared for upstream.

# Patches prepared for upstream

Series prepared under [../UPSTREAM_POLICY.md](../UPSTREAM_POLICY.md) stage 1
go here, one directory per repository (`git format-patch` output), with a
line per series below: what it is, its test counts, its review state.

| Series | Patches | Tests | State |
|---|---|---|---|
| libs-back: dragging files out (XDND), `~/git/gnustep/libs-back-xdnd` on master `36ac709` | `libs-back/0001-...` (`5bcfb0b`), `0002-...` (`7be8987`) | xdndfilenames 9/9 (7 fail on master); xdndversion 7/7 (5 fail before); suite 300 passed, 0 failed (master 286 + 7 failed) | prepared 2026-10-16 ([review](review/libs-back-xdnd.md)); Dan chose to carry them in the Linux packages first (`packaging/patches/libs-back/0002`, `0003`) and live with them before review and sending |
| libs-back: copied files on the clipboard (xpbs), `~/git/gnustep/libs-back-clipfiles` on master `36ac709` | `libs-back/0003-...` (`c5c9fad`) | xpbscopiedfiles 9/9 (the file checks fail with an unpatched gpbs); suite 264 passed, 22 failed, the same 22 failures as master (255 passed) in the same environment, from tests run against the installed backend | prepared 2026-10-16 ([review](review/libs-back-xpbs-copied-files.md)); carried in the Linux packages first (`packaging/patches/libs-back/0004`) |

The patches the Linux packages carry are in `packaging/patches/`; they
aren't prepared for upstream.

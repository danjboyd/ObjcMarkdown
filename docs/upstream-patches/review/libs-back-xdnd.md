# Review: libs-back, dragging files out to other apps (XDND)

Two commits on libs-back master `36ac709`, in `~/git/gnustep/libs-back-xdnd`
(branch `ai-policy/xdnd-file-drags`), prepared under
[../../UPSTREAM_POLICY.md](../../UPSTREAM_POLICY.md). Found while building
Share (#170, #175): the file in the Share dialog can be dragged, but no other
app would take it.

| Item | Commit | What |
|---|---|---|
| libs-back 0001 | `5bcfb0b67ac45d39c8e3d96948315ced8371ee5a` | answer TARGETS and text/uri-list for drags, refuse the rest |
| libs-back 0002 | `7be8987273ea3922da71278f041532193a93a2db` | speak XDND version 3, and send what each version needs |

Neither is enough alone for a drop on a GTK app; with both, a file dragged
from MarkdownViewer onto Nautilus is copied into the folder. They are separate
changes (one in the selection handler, one in the XDND messages) and each
builds and passes its own test alone.

## How a drag to another app works (XDND)

1. The source (GNUstep) takes ownership of the `XdndSelection` and sends the
   target window an **XdndEnter** with its protocol version and its data
   types (`text/uri-list` for files).
2. While the pointer moves it sends **XdndPosition** (position, time stamp,
   action such as copy); the target answers **XdndStatus** (accept or not).
3. On release it sends **XdndDrop**; the target then asks for the data with an
   ordinary X selection request on `XdndSelection` (ICCCM): usually first
   `TARGETS` (which types are there?), then one type.

GNUstep failed at three points, each found by a run:

- It answered only the string types. GTK's first request, `TARGETS`, got no
  reply at all, not even a refusal; neither did `text/uri-list`.
  (Patch 0001.)
- It announced **version 2**. GTK ignores that: with `GDK_DEBUG=dnd` Nautilus
  logs `XdndEnter: ... version: 0x2` and `Ignored old XdndEnter message`. The
  spec's change log (1998-09-07) says compliance requires version 3 and up.
  (Patch 0002.)
- Announcing version 3 then showed that `dnd_version_at_least()` is inverted:
  `((a) <= (b))`. At version 3 the drag sent neither the time stamp nor the
  action, and GTK logged `action: 0`, so Nautilus couldn't accept. At version 2
  it had sent the action but never a time stamp (`time: 0` in GTK's log).
  (Patch 0002.)

## 0001, hunk by hunk (`Source/x11/XGServerEvent.m`)

- **`#include <Foundation/NSURL.h>`**: used for `+fileURLWithPath:`.
- **`sendSelectionNotify()`** (new static function): the reply ICCCM requires
  after a selection request, with the property holding the data, or `None` to
  refuse. `xdnd_selection_send()` (existing) does the same but only for 8-bit
  data, so it can't carry the 32-bit atom list for `TARGETS`, nor a refusal.
- **In the `SelectionRequest` case:**
  - `TARGETS`: builds the list from what the drag pasteboard has: always
    `TARGETS`; `UTF8_STRING`, `STRING`, `TEXT` for a string; `text/uri-list`
    for file names. Written as 32-bit atoms, then notify, then `break` (the
    rest of the case is for data).
  - `text/uri-list` with `NSFilenamesPboardType`: each path through
    `NSURL fileURLWithPath:` -> `absoluteString`, so spaces become `%20`; one
    per line, each ending in CRLF (RFC 2483), UTF-8.
  - The string branch is unchanged.
  - If nothing was produced: notify with `None` (refuse) at once. Before, it
    sent nothing and the requester waited for its own time-out. GTK asks for
    two portal types first (`application/vnd.portal.filetransfer`,
    `...portal.files`) and now gets an immediate refusal for each.
- `request` is just a name for `&xEvent.xselectionrequest`.

**ChangeLog** entry; **`Tests/x11/xdndfilenames.m`** (new).

## 0002, hunk by hunk

- **`Headers/x11/xdnd.h`**: `XDND_VERSION` 2 -> 3, with a comment. Version 3
  only moved `XdndAware` to the top-level window, where this backend already
  sets it (on each GNUstep window's own X window). This value is both what the
  drag announces and what `XdndAware` advertises to other apps' drags.
- **`Source/x11/xdnd.c`, `dnd_version_at_least`**: `<=` -> `>=`. Its four
  callers: XdndPosition time (>=1), XdndPosition action (>=2), XdndDrop time
  (>=1), XdndStatus action (>=2).
- **`xdnd_send_status`**: drop the version test, keep `if (will_accept)`.
  XdndStatus is sent when a GNUstep window is the *target*, and that side never
  records the source's version, so `dragging_version` is whatever the app's
  own last drag left (0 at first). With the corrected comparison, the action
  would have stopped being sent to every source. Sending it always is what
  happened before for every version up to 2; versions 0 and 1 treat that word
  as reserved.

**ChangeLog** entry; **`Tests/x11/xdndversion.m`** (new).

## Tests and results (all run 2026-10-16)

Each backend build was loaded alone: a private `GNUstep.conf` (0644) whose
user Library held only that build's bundle, empty defaults, a private Xvfb;
`LD_DEBUG=files` confirmed the bundle loaded. libs-gui and libs-base were the
installed ones.

| Run | New test | Whole suite |
|---|---|---|
| master `36ac709` + test 0001 | xdndfilenames: 7 of 9 fail | 286 passed, 7 failed |
| 0001 `5bcfb0b` | xdndfilenames: 9 of 9 pass | 293 passed, 0 failed |
| 0001 + test 0002, xdnd.c unchanged | xdndversion: 5 of 7 fail | 295 passed, 5 failed |
| 0002 `7be8987` | xdndversion: 7 of 7 pass; xdndfilenames: 9 of 9 | 300 passed, 0 failed |

Every run also has `pdfps.m` aborting before its checks, on master too:
libs-gui's font-roles bug in the installed snapshot, fixed on gui master
(8a092cfa7).

- **xdndfilenames.m** plays the drop target from a second X connection. The
  owner of `XdndSelection` is set on the *backend's* connection, as a drag
  does. The X server sends the request to whichever client set the owner; my
  first version set it from the test's connection and got its own request
  back. Two of its checks pass on master: the unchanged string answer, and
  "doesn't offer UTF8_STRING", which holds when nothing answers.
- **xdndversion.m** `#include`s `xdnd.c`, like the other x11 tests do with
  their sources, sends each message to a window it created, and reads it back.
  The two XdndStatus checks pass before the change, and are there to show the
  target side didn't change.

**Real drop, GNOME Shell on Xvfb, Nautilus as the target**, MarkdownViewer's
Share dialog as the source, with a backend built from the tree that matches
the installed one (`libs-back-csd` plus its uncommitted CSD work) plus both
patches:
- the file appeared in the folder, `cmp`-identical to the exported file;
- Nautilus's `GDK_DEBUG=dnd` log: `version: 0x3`, `DND formats:
  text/uri-list`, `XdndPosition ... action: 399` with times, two portal types
  refused, `reading DND as text/uri-list now`;
- with 0001 only: `Ignored old XdndEnter message`; with the version raised but
  the macro still inverted: `action: 0`; on the installed backend: no drop.

**GCC check** (`tools/upstream/gcc-syntax-check.sh ~/git/gnustep/libs-back-xdnd`):
exit 0. The canary is rejected; `XGServerEvent.m`, `xdnd.c` and both tests are
`ok`; `xdnd.h` is checked through its includers. 0001 alone: also exit 0.

**Patches**: `docs/upstream-patches/libs-back/0001-...patch` and `0002-...patch`
(`git format-patch origin/master`); `git am` onto `36ac709` gives the same
tree as `7be8987` (0 lines of diff).

## Risky, uncertain or not tested

- **Drops *into* GNUstep from GTK apps**: not shown either way. The editable
  text view I tried takes no file drops with or without the patches. Change
  0002 raises what GNUstep advertises in `XdndAware` to version 3, so GTK
  sources will send version 3 messages. Those have the same layout as
  version 2; the difference is only where `XdndAware` sits.
- **Time stamps**: now sent. XdndDrop's comes from the release event (an X
  event, so X server time); XdndPosition's come from the drag loop's
  NSEvents. In the run they jumped between two scales (18472000 and
  2129272129). The target uses the drop's time for its data request, and
  that worked. A position time stamp from the wrong clock is a pre-existing
  oddity that is now visible; it's in the commit message's "Not covered".
- **XdndEnter** still announces the backend's version, not min(source,
  target) as the spec says. Every compliant target supports 3, so they agree.
  Fixing it would touch `xdnd_is_dnd_aware`'s callers; left out.
- **Not tried**: browsers (Gmail), Evolution, KDE apps, Wayland-native targets
  through XWayland. All need these patches first.
- **Only X11**: the Wayland backend and win32 aren't touched.

## Questions to be able to answer

- *Why not reuse `xdnd_selection_send` for TARGETS?* It writes 8-bit data
  only; TARGETS is a list of 32-bit atoms.
- *Why refuse unknown types now?* ICCCM says the owner must reply. Without a
  reply the requester waits for its time-out (GTK's portal types first).
- *Why always send the XdndStatus action?* The target side doesn't know the
  source's version. This keeps exactly today's behaviour; the old inverted
  check let it through for every version up to 2.
- *Why version 3, not 5?* 3 is the minimum for compliance and needs nothing
  new from us. 4 adds `XdndProxy` and 5 adds fields to XdndFinished; each would
  need code we don't have.

## To check it yourself

```
cd ~/git/gnustep/libs-back-xdnd
git show 5bcfb0b          # 0001
git show 7be8987          # 0002
```

To watch the tests run, ask Claude to run
`run-back-test.sh <bundle> ~/git/gnustep/libs-back-xdnd x11/xdndfilenames.m`
(it's in that session's scratch directory), or the real drop with you
watching the private display.

## Sign-off

Approve each item in the chat ("I approve libs-back 0001", "I approve
libs-back 0002") and Claude records it, or add the rows to
`docs/UPSTREAM_SIGNOFF.md` yourself:

```
| <date> | libs-back 0001 | 5bcfb0b67ac45d39c8e3d96948315ced8371ee5a | | |
| <date> | libs-back 0002 | 7be8987273ea3922da71278f041532193a93a2db | | |
```

Approving isn't sending: they go upstream, one pull request each, only when
you ask for that item.

## Carried in our Linux packages first

Dan decided on 2026-10-16 to carry both in the AppImage and Flatpak and live
with them before reviewing and sending them: `packaging/patches/libs-back/0002`
and `0003`, the same source changes rebased onto the libs-back pin `23fbe39`
after the carried WM_DELETE_WINDOW patch (0001). On that pinned tree both new
tests pass (xdndfilenames 9/9, xdndversion 7/7). Anything found while living
with them goes into this series before review; the hashes above change then.

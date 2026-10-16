# Review: libs-back, copied files on the clipboard (xpbs)

One commit on libs-back master `36ac709`, in `~/git/gnustep/libs-back-clipfiles`
(branch `ai-policy/clipboard-file-copies`), prepared under
[../../UPSTREAM_POLICY.md](../../UPSTREAM_POLICY.md). Found while building
Share's Copy (#170, #193).

| Item | Commit | What |
|---|---|---|
| libs-back 0003 | `c5c9fadf0a71e6fdf5b8c1e2f5b08bd48f49fae0` | xpbs: offer copied files as text/uri-list and x-special/gnome-copied-files |

Carried in the Linux packages as `packaging/patches/libs-back/0004-...`
(the same change on the pin `23fbe39`, after the XDND patches).

## The problem

gpbs's X side (`Tools/xpbs.m`) puts the general pasteboard on the X
`CLIPBOARD` selection. For file names (`NSFilenamesPboardType`) it offered
only `FILE_NAME`, with the last file as a `file://localhost` URI. File
managers don't read `FILE_NAME`: they paste copied files from
`x-special/gnome-copied-files` (GNOME Files, Nemo, Caja, Thunar) or
`text/uri-list` (GNOME Files 4x, Dolphin). So a file copied in a GNUstep
app could not be pasted into them.

MarkdownViewer itself got around this already: libs-sharing's Copy also
writes `NSURLPboardType` as `text/uri-list` bytes, and GNOME Files 48 pastes
from that (checked with the stock gpbs on the private session). Other
GNUstep apps that copy files set only `NSFilenamesPboardType`, and the file
managers that read only `x-special/gnome-copied-files` still got nothing.

## The change, hunk by hunk (`Tools/xpbs.m`)

- **`atom_names` / `XG_GNOME_COPIED_FILES`**: one more atom, interned with
  the others at start-up.
- **TARGETS**: with file names, after `FILE_NAME`, also `text/uri-list`
  (only if no `NSURLPboardType` is there, which already answers it, so it
  isn't listed twice) and `x-special/gnome-copied-files`. The `xTypes`
  array grows from 23 to 25 for the two.
- **The conversion** (a new branch before TIFF): `text/uri-list` is every
  file as `+[NSURL fileURLWithPath:]`'s URI, each line ending in CRLF
  (RFC 2483), the same format the XDND patch sends for drags;
  `x-special/gnome-copied-files` is `copy`, then `\n` and a URI per file,
  with no trailing newline. Always a copy: GNUstep's pasteboard doesn't
  say whether files were cut.
- An `NSURLPboardType` keeps answering `text/uri-list` as before (its branch
  comes first). `FILE_NAME` is unchanged.

## Test (`Tests/x11/xpbscopiedfiles.m`, new)

Puts two files on the general pasteboard (one with a space in its path),
waits for gpbs to take `CLIPBOARD`, and asks from its own X connection, as a
pasting client does: `TARGETS` lists both new types and still `FILE_NAME`;
`text/uri-list` and `x-special/gnome-copied-files` have the exact bytes
(percent-escaped, CRLF and `\n` respectively). Then text: `UTF8_STRING` still
answers, and neither file type is listed. 9 checks.

It needs the gpbs from the tree under test running (the suite uses whatever
gpbs is up, or starts the installed one); it skips if no gpbs takes
`CLIPBOARD`. With the patched gpbs: 9/9. With the unpatched installed gpbs
the file checks fail, so it guards the change.

Suite, same Xvfb and private config, patched gpbs running: 264 passed, 22
failed tests and 2 failed files; master's gpbs: 255 passed and the same 22 and
2 (diffed). Those failures are drawing and font tests run against the
installed backend bundle (the pin), not this tree.

By hand (GNOME Shell on Xvfb, the private session): Share > Copy in
MarkdownViewer, then Ctrl+V in GNOME Files 48 pasted `Sample.docx` into
the folder, with the carried gpbs and also with the stock one (see above
for why). Not yet tried by hand: Nemo, Caja, Thunar, which read only
`x-special/gnome-copied-files`.

## For Dan

- Read the diff (about 50 lines) and the test.
- The open question above: try a paste in one of Nemo, Caja or Thunar
  before sending, so the description's claim about them is checked.

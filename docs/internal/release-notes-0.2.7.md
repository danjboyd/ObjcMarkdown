# Release notes: 0.2.7

Draft, 2026-11-03 (markdown-viewer-macos, for objcmarkdown-lead).
Changes are counted from v0.2.6 (e35c655). Milestone "0.2.7".
Bullets marked "pending" describe open PRs; drop or move them if the PR
misses rc1.

---

**New since 0.2.6**
- Read view: Edit Block opens a paragraph's Markdown in place and renders it again when you're done (#294). Pending: the spike (#332, paragraphs only) decides whether it ships in 0.2.7.

**Fixed since 0.2.6**
- macOS: Split keeps the ratio you dragged. New tabs no longer open with the preview at about 15% (#312).
- macOS: with a mouse attached (legacy scroll bars), the preview no longer shows a horizontal scroll bar after a relaunch in Split (#319, #320).
- macOS: code lines, list items and paragraphs no longer get extra space after each line. The layout matches Linux and Windows (#321, #322).
- Linux (and likely Windows): Show in Folder in the Share panel selects the saved document, not a temporary copy (#304, #311).
- Pending: Windows and Linux, closing the launch window's tab and opening its document again no longer brings the closed window back outside the tab group (#323, #326).
- Pending: Show in Folder selects the document for any saved Markdown extension (`.markdown`, `.MD`, `.mdown`, and `.TXT` in plain-text mode), not only `.md` (#265, #327).
- Pending: Windows, typing in the source editor recolours only what changed (#164, #328; the CPU-per-key figure goes here once it's measured).
- Pending: Windows, dark mode: math draws in the theme's text colour on the page, not as a white patch (#324, #330).
- Pending: Windows, the Share panel's Email notice names the saved document (#304, branch `share-panel-email-304`).
- Pending: Builds: the Linux packages bundle Adwaita 0.1.0-alpha19 (#316), and packaging moves to gnustep-packager v0.1.6 (#313).

**Known issues** (carried over from 0.2.6 unless fixed above; to be confirmed in the rc1 rounds)
- Windows at 150%: a short black bar at the bottom left of the source pane cuts off the last line (#325). It may be the backend (carry-0.32.0.5); compare with carry-0.32.0.4.
- Linux: Split view can stall on large documents (#318). The libs-gui text-cache fix is going upstream first.
- Linux AppImage: opening a second file starts a second copy of the app (#309). Not a regression.
- Linux: the bundled notification service (gdnc) keeps running after the app quits.
- macOS with window restoration on: the restored documents come back in reversed tab order.
- Linux and Windows: shortcodes whose emoji is outside the BMP stay as typed (#267).

---

## Plan

**Merged**

| PR | What | State |
|---|---|---|
| #311 | #304 Linux: the Share panel's Show in Folder selects the document | merged cdf52f7 |
| #312 | macOS: Split keeps the dragged ratio; only a divider drag saves it | merged 9a67b80; on-screen PASS (Dan, ask #981) |
| #171 | Share design note, refreshed after 0.2.6 | merged fb565d9 |
| #320 | #319 macOS: the preview is laid out beside a legacy vertical scroller | merged 0a91116 |
| #322 | #321 macOS: no paragraph spacing, as on GNUstep | merged 4edfde3; in-app PASS light and dark (Dan, ask #1733) |
| #329 | Lead handoff 2026-11-03 | merged a4680c5 |

**Open**

| PR / branch | What | State |
|---|---|---|
| #326 | #323 a closed launch window isn't revived (`OMDWindowIsOpen()`) | green on all three platforms; Windows on-screen check pending |
| #327 | #265 any saved Markdown extension counts as the document for Show in Folder | green; Windows on-screen check pending |
| #328 | #164 the source highlighter sets only changed colours | green; CPU per key to be measured against the ~44 ms baseline |
| #330 | #324 Windows math: premultiplied pixels, themed ink (draft) | Windows MSI check in dark and light |
| `share-panel-email-304` | #304 Windows: the Share panel's Email uses the app's presenter | local (markdown-viewer-windows) |
| #332 | #294 Edit Block spike: paragraphs only, with the minimal-edit test (draft) | go/stop in the morning report |
| #316, #313 | Adwaita alpha19; gnustep-packager v0.1.6 | markdown-viewer-linux |

## Checklist

- [ ] Scope for rc1 (Dan): which of #326, #327, #328, #330, #304 Email, #316, #313 and Edit Block are in.
- [ ] Merge round (Dan's go, after each PR's on-screen check).
- [ ] Packaging green on the rc1 commit, untagged: AppImage, Flatpak, MSI, dmg. Record the theme commits: the AppImage's and the MSI's BundledThemes.txt (Adwaita, and WinUITheme with its libs-back carry).
- [ ] `v0.2.7-rc1` tagged (Dan): tag workflows green, assets complete, pre-release, stable feeds untouched.
- [ ] rc1 rounds on the CI packages, not dev builds:
  - **Windows** (the MSI on an OracleTestVMs lease through the gate):
    - BundledThemes.txt names the bundled WinUITheme commit.
    - #323 (#326): close the launch window's tab, open its document again. It opens as a tab in the remaining window; the closed window stays closed.
    - #265 (#327): Show in Folder after sharing a saved `.markdown`, `.MD` and `.mdown` document selects that document.
    - #304: the Share panel's Show in Folder (the tile) and the Email notice name the saved document.
    - #164 (#328): CPU per key while typing in the source editor, measured the same way as the ~44 ms/key baseline.
    - #324 (#330): WinUITheme dark at 100%, `$$x^2$$` and an inline `$E = mc^2$` draw in the light text colour on the page, with no white patch. Light mode and printing still draw dark math.
    - #325: at 150%, the bar over the source pane's last line. Compare with carry-0.32.0.4; if it's the backend, file it on plugins-themes-winuitheme.
    - The in-app update from 0.2.6 to rc1 through the rc1 feed, and the #266 reopen in tab order.
  - **macOS** (the dmg):
    - An update from 0.2.6 through Sparkle (a localhost copy of the rc1 appcast, EdDSA checked, automatic updates off on the scratch copy). The updated app is byte-identical to the dmg's; About shows 0.2.7-rc1; the open documents reopen in tab order with the same one selected.
    - #312: drag the divider, then open a new tab in Split, switch modes and relaunch. The dragged ratio holds, and only the drag saves it.
    - #319 (#320): with a mouse attached (legacy scroll bars), relaunch in Split. There's no horizontal scroll bar under the preview.
    - #321 (#322): smoke.md and a long document in light and dark. Code lines, list items and paragraphs are tight, and the code-block card and quote bar show.
    - Edit Block (if in): open a paragraph, type, close, undo. The source changes only inside the paragraph.
  - **Linux** (AppImage and Flatpak, isolated: private display, home and defaults):
    - BundledThemes.txt names Adwaita alpha19 (207f446) if #316 is in.
    - #304 (#311): the Share panel's Show in Folder selects the saved document.
    - An update from 0.2.6 through a local signed feed (tools/dev/update-test), with the #266 reopen in tab order.
    - Header bar, menus and the Share panel under Adwaita; the window manager's title bar under GNUstep's default theme.
    - Edit Block (if in): the main hazard is GNUstep's text system. Check the caret, selection and typing in the open block, under both the GNUstep theme and Adwaita.
- [ ] Known issues confirmed or updated from the rounds.
- [ ] Dan: go for v0.2.7 final.

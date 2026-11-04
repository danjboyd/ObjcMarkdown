# Release notes: 0.2.7

Draft, 2026-11-03, updated 2026-11-04 (markdown-viewer-macos, for objcmarkdown-lead).
Changes are counted from v0.2.6 (e35c655). Milestone "0.2.7".
Bullets marked "pending" describe open PRs; drop or move them if the PR
misses rc1.

---

**New since 0.2.6**
- None planned. Edit Block (#294) moved to 0.2.8 (Dan, ask #2054); the spike goes on in draft #332.

**Fixed since 0.2.6**
- macOS: Split keeps the ratio you dragged. New tabs no longer open with the preview at about 15% (#312).
- macOS: with a mouse attached (legacy scroll bars), the preview no longer shows a horizontal scroll bar after a relaunch in Split (#319, #320).
- macOS: code lines, list items and paragraphs no longer get extra space after each line. The layout matches Linux and Windows (#321, #322).
- Linux (and likely Windows): Show in Folder in the Share panel selects the saved document, not a temporary copy (#304, #311).
- Pending: Windows and Linux, closing the launch window's tab and opening its document again no longer brings the closed window back outside the tab group (#323, #326).
- Pending: Show in Folder selects the document for any saved Markdown extension (`.markdown`, `.MD`, `.mdown`, and `.TXT` in plain-text mode), not only `.md` (#265, #327).
- Pending: Windows, dark mode: math draws in the theme's text colour on the page, not as a white patch (#324, #330).
- Pending: Windows, the Share panel's Email notice names the saved document (#304, branch `share-panel-email-304`).
- Pending: Linux and Windows, the app no longer writes six keys into the global defaults domain (NSGlobalDomain), where they reached every GNUstep app (#335).
- Pending: Preferences no longer shows Menu Bar under the menu button when the Menus setting has never been set (#334).
- Pending: Linux, switching from Read to Split again on a large document is about three times cheaper: about 1.6 s of CPU instead of about 5 s on a 460 KB document (#318, partial fix 4768d30).
- Pending: Builds: the Linux packages bundle Adwaita 0.1.0-alpha22 (d274272, #316, PR #336), and the Flatpak starts with the menu button, as the AppImage does (`GnomeThemeMenuStyle = primary`). Packaging moves to gnustep-packager v0.1.7 (#313, PR #337).

**Known issues** (carried over from 0.2.6 unless fixed above; to be confirmed in the rc1 rounds)
- Windows at 150%: a short black bar at the bottom left of the source pane cuts off the last line (#325). It isn't the backend carry: it looks the same with carry-0.32.0.4 as with 0.32.0.5.
- Windows: typing in the source editor costs about as much CPU per key as in 0.2.6. #328 cut the redraws by about 35% but not the time per key (about 42 ms before, 47 ms after), so it isn't in rc1 (#164 stays open; #333 covers colouring large documents).
- Linux: Split view can still stall on large documents (#318). The partial fix above cuts the later switches; the libs-gui text-cache fix is going upstream first.
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
| #328 | #164 the source highlighter sets only changed colours | OUT of rc1: CPU per key ~42 -> ~47 ms although draws fell ~35%; #164 open, #333 filed |
| #330 | #324 Windows math: premultiplied pixels, themed ink (draft) | Windows only (rc2's MSI shows the white patch too); in the uat2 check |
| `share-panel-email-304` | #304 Windows: the Share panel's Email uses the app's presenter | local (markdown-viewer-windows) |
| #332 | #294 Edit Block spike (draft) | moved to 0.2.8 (Dan, #2054); not in 0.2.7 |
| #336 | #316 Linux packages: Adwaita alpha22 (d274272); the Flatpak seeds `GnomeThemeMenuStyle = primary` like the AppImage (Dan) | merging on green (Dan, #2383). markdown-viewer-linux |
| #337 | #313 gnustep-packager v0.1.7 | pending: the MSI comparison. markdown-viewer-linux |
| 4768d30 | #318 partial: later Read-to-Split switches ~5 s -> ~1.6 s CPU on 460 KB | pending: push asked (#2497). markdown-viewer-linux |
| #334 | Preferences shows Menu Bar under the menu button when the Menus setting is unset | 0.2.7 item |
| #335 | Six keys written into NSGlobalDomain on GNUstep | 0.2.7 item |

## Checklist

- [ ] Scope for rc1 (Dan): which of #326, #327, #330, #304 Email, #316 (#336), #313 (#337), #318 (4768d30), #334 and #335 are in (#328 and Edit Block are out).
- [ ] Merge round (Dan's go, after each PR's on-screen check).
- [ ] Packaging green on the rc1 commit, untagged: AppImage, Flatpak, MSI, dmg. Record the theme commits: the AppImage's and the MSI's BundledThemes.txt (Adwaita, and WinUITheme with its libs-back carry).
- [ ] `v0.2.7-rc1` tagged (Dan): tag workflows green, assets complete, pre-release, stable feeds untouched.
- [ ] rc1 rounds on the CI packages, not dev builds:
  - **Windows** (the MSI on an OracleTestVMs lease through the gate):
    - BundledThemes.txt names the bundled WinUITheme commit.
    - #323 (#326): close the launch window's tab, open its document again. It opens as a tab in the remaining window; the closed window stays closed.
    - #265 (#327): Show in Folder after sharing a saved `.markdown`, `.MD` and `.mdown` document selects that document.
    - #304: the Share panel's Show in Folder (the tile) and the Email notice name the saved document.
    - #324 (#330): WinUITheme dark at 100%, `$$x^2$$` and an inline `$E = mc^2$` draw in the light text colour on the page, with no white patch. Light mode and printing still draw dark math.
    - #325: at 150%, the bar over the source pane's last line is still there (known issue; not the backend carry).
    - The in-app update from 0.2.6 to rc1 through the rc1 feed, and the #266 reopen in tab order.
  - **macOS** (the dmg):
    - An update from 0.2.6 through Sparkle (a localhost copy of the rc1 appcast, EdDSA checked, automatic updates off on the scratch copy). The updated app is byte-identical to the dmg's; About shows 0.2.7-rc1; the open documents reopen in tab order with the same one selected.
    - #312: drag the divider, then open a new tab in Split, switch modes and relaunch. The dragged ratio holds, and only the drag saves it.
    - #319 (#320): with a mouse attached (legacy scroll bars), relaunch in Split. There's no horizontal scroll bar under the preview.
    - #321 (#322): smoke.md and a long document in light and dark. Code lines, list items and paragraphs are tight, and the code-block card and quote bar show.
  - **Linux** (AppImage and Flatpak, isolated: private display, home and defaults):
    - BundledThemes.txt names Adwaita alpha22 (d274272) if #316 is in, and the app launches with it. A fresh Flatpak install starts with the menu button, like the AppImage.
    - #318: on a large document, the second and later switches from Read to Split are quicker than in 0.2.6.
    - #334 and #335: with the Menus setting never set, Preferences shows the menu button; after a session, NSGlobalDomain holds none of the app's keys.
    - #304 (#311): the Share panel's Show in Folder selects the saved document.
    - An update from 0.2.6 through a local signed feed (tools/dev/update-test), with the #266 reopen in tab order.
    - Header bar, menus and the Share panel under Adwaita; the window manager's title bar under GNUstep's default theme.
- [ ] Known issues confirmed or updated from the rounds.
- [ ] Dan: go for v0.2.7 final.

# Release notes: 0.2.7

Draft, 2026-11-03, updated 2026-11-04 (markdown-viewer-macos) and 2026-11-06 (objcmarkdown-lead, the rc1 merge round).
Changes are counted from v0.2.6 (e35c655). Milestone "0.2.7".

---

**New since 0.2.6**
- None planned. Edit Block (#294) moved to 0.2.8 (Dan, ask #2054); the spike goes on in draft #332.

**Fixed since 0.2.6**
- macOS: Split keeps the ratio you dragged. New tabs no longer open with the preview at about 15% (#312).
- macOS: with a mouse attached (legacy scroll bars), the preview no longer shows a horizontal scroll bar after a relaunch in Split (#319, #320).
- macOS: code lines, list items and paragraphs no longer get extra space after each line. The layout matches Linux and Windows (#321, #322).
- Linux and Windows: Show in Folder in the Share panel selects the saved document, not a temporary copy (#304, #311).
- Windows: the Share panel's Email notice shows the saved document in its folder, not the temporary copy (#304, #365).
- Windows and Linux: closing the launch window's tab and opening its document again no longer brings the closed window back outside the tab group (#323, #326).
- Show in Folder selects the document for any saved Markdown extension (`.markdown`, `.MD`, `.mdown`, and `.TXT` in plain-text mode), not only `.md` (#265, #327).
- Windows, dark mode: math draws in the theme's text colour on the page, not as a white patch (#324, #330).
- Linux: switching from Read to Split again on a large document is about three times cheaper: about 1.6 s of CPU instead of about 5 s on a 460 KB document (#318, partial fix #338).
- Builds: the Linux packages bundle Adwaita 0.1.0-alpha22 (d274272, #316, #336), and the Flatpak starts with the menu button, as the AppImage does (`GnomeThemeMenuStyle = primary`). The AppImage's packaging moves to gnustep-packager v0.1.7 (#313, #337); the MSI stays on v0.1.4 for 0.2.7 (its move is #339, in 0.2.8).

**Not in rc1, candidates for rc2** (they need a Windows first-launch check first)
- Linux and Windows: the app no longer writes six keys into the global defaults domain (NSGlobalDomain), where they reached every GNUstep app (#335, #341). Keys that earlier versions wrote stay where they are, as they can't be told apart from a user's own choice (Dan, ask #3244). To remove them: `defaults delete NSGlobalDomain NSMenuInterfaceStyle`, and the same for `GSWindowDecoration`, `GSBackChecksOffsetsWithoutNetRequests`, `GSBackChecksOffsetsOnScreen` and `GSSuppressAppIcon` (and `GSTheme`, if you didn't choose it).
- Preferences no longer shows Menu Bar under the menu button when the Menus setting has never been set (#334, #345).

**Known issues** (carried over from 0.2.6 unless fixed above; to be confirmed in the rc1 rounds)
- Windows at 150%: a short black bar at the bottom left of the source pane can cut off the last line (#325). The theme adding a horizontal scroller the app didn't ask for is the likely cause; it didn't reproduce in the 2026-11-06 round on either 0.2.6 or the rc build, so it isn't confirmed fixed.
- Windows: typing in the source editor costs about 70 ms of CPU per key on a large document (#164). The cause is found (libs-gui redraws a control on every `setEnabled:`), and its fix (#361, about −44%) is for 0.2.8.
- Windows: Print, Export as PDF and Share as PDF show math as readable text, not typeset (#364). This has been so since #226.
- Linux: Split view can still stall on large documents (#318). The partial fix above cuts the later switches; the rest is 0.2.8's performance work (#346).
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
| #336 | #316 Linux packages: Adwaita alpha22 (d274272); the Flatpak seeds `GnomeThemeMenuStyle = primary` like the AppImage (Dan) | merged 0f1dd60; CI's AppImage and Flatpak pass a launch check |
| #337 | #313 gnustep-packager v0.1.7, AppImage only | merged ed5a4b7 |
| #338 | #318 partial: later Read-to-Split switches ~5 s -> ~1.6 s CPU on 460 KB | merged fa57426 (Dan, ask #2642); macOS on-screen PASS |
| #326, #327, #330, #365 | #323, #265, #324, #304 Email | merged 2026-11-06 (Dan, ask #4149) after the Windows round on the uat2 MSI |

**Windows round, 2026-11-06** (the installed uat2 MSI, 0.2.7-uat2 = main 53da408 + #326, #327, #328, #330 and the #304 branch; WinUITheme 72f2a10, libs-back carry-0.32.0.5; an OracleTestVMs lease):
- #326 PASS: the launch tab closed while selected (and, on 11-05, while in the background), then its document opened again: one window, as a tab.
- #327 PASS: `UPPER.MD` saved, then Show in Folder selects it. `.markdown` wasn't run.
- #304 PASS: the tile's and the Email notice's Show in Folder both select the document. The Email notice's icon is generic (cosmetic).
- #330 PASS: dark mode, display and inline math readable, no white patch; a faint lighter block shows behind display math (noted on #330). Light mode fine.
- #325: not reproduced at a real 150% on 0.2.6 or uat2 (three widths, the theme's scroller trace on).
- #164: CPU per key on the same lease, 0.2.6 about 71 ms, uat2 about 45 ms, #361's MSI about 40 ms.
- Not run (the lease was released for another project): a 0.2.6 print comparison, the 125% resize, `.markdown`.

**Open, not in rc1**

| PR / branch | What | State |
|---|---|---|
| #328 | #164 the source highlighter sets only changed colours | out of 0.2.7 (Dan, ask #4149); 0.2.8's #342 and #358 replace it |
| #341 | #335 defaults out of NSGlobalDomain | green; Linux and local-Flatpak PASS; Windows first launch to check; rc2 candidate |
| #345 | #334 Preferences shows the drawn menu style | green; Linux PASS; Windows to check; rc2 candidate |
| #332 | #294 Edit Block spike (draft) | moved to 0.2.8 (Dan, #2054) |
| #355 | #339 the MSI on gnustep-packager v0.1.7 | 0.2.8; launches with the clang 23 workaround; needs an MSI round |

## Checklist

- [x] Scope for rc1 (Dan, ask #4149): #326, #327, #330, #304 Email (#365), with #337 and #338 already in; #328, #341 and #345 out.
- [x] Merge round (Dan, ask #4149).
- [ ] Packaging green on the rc1 commit, untagged: AppImage, Flatpak, MSI, dmg. Record the theme commits: the AppImage's and the MSI's BundledThemes.txt (Adwaita, and WinUITheme with its libs-back carry).
- [ ] `v0.2.7-rc1` tagged (Dan): tag workflows green, assets complete, pre-release, stable feeds untouched.
- [ ] rc1 rounds on the CI packages, not dev builds:
  - **Windows** (the MSI on an OracleTestVMs lease through the gate, slot agreed with gnustep-tools-lead):
    - BundledThemes.txt names the bundled WinUITheme commit.
    - A smoke of the 11-06 checks on the rc1 MSI (#326, #327 with `.markdown`, #304, #330).
    - #325: at 150%, launched from a saved narrow frame.
    - The in-app update from 0.2.6 to rc1 through the rc1 feed, and the #266 reopen in tab order.
  - **macOS** (the dmg; `rc-round.sh`):
    - An update from 0.2.6 through Sparkle (a localhost copy of the rc1 appcast, EdDSA checked, automatic updates off on the scratch copy). The updated app is byte-identical to the dmg's; About shows 0.2.7-rc1; the open documents reopen in tab order with the same one selected.
    - #312: drag the divider, then open a new tab in Split, switch modes and relaunch. The dragged ratio holds, and only the drag saves it.
    - #319 (#320): with a mouse attached (legacy scroll bars), relaunch in Split. There's no horizontal scroll bar under the preview.
    - #321 (#322): smoke.md and a long document in light and dark. Code lines, list items and paragraphs are tight, and the code-block card and quote bar show.
  - **Linux** (AppImage and Flatpak, isolated: private display, home and defaults; `linux-rc-round.sh --tag v0.2.7-rc1 --from v0.2.6 --theme d274272`):
    - BundledThemes.txt names Adwaita alpha22 (d274272), and the app launches with it.
    - Flatpak menus: on a first run in a fresh home, the menu button shows and Preferences says Menu Button. An existing Flatpak user with no Menus key gets the same seed.
    - #318 (#338): on a long document, switching Read, Split and Edit, the second and later switches to Split are quicker than in 0.2.6. A dragged divider's ratio is kept across the switches, and through a window resize.
    - #304 (#311): the Share panel's Show in Folder selects the saved document.
    - An update from 0.2.6 through a local signed feed (tools/dev/update-test), with the #266 reopen in tab order.
    - Header bar, menus and the Share panel under Adwaita; the window manager's title bar under GNUstep's default theme.
- [ ] Known issues confirmed or updated from the rounds.
- [ ] Dan: go for v0.2.7 final.

# Release notes: 0.2.6

Linux leads it; ReleaseCoordinator coordinates.
Changes are counted from v0.2.5 (ba4f6ff). Milestone "0.2.6" (4).

---

**New since 0.2.5**
- Read view: click a task checkbox to tick or untick it; the file's `[ ]`/`[x]` changes (#285).
- Read view: Reveal in Source jumps from any block to its Markdown in the editor (#293).
- After an in-app update the app reopens the documents that were open, in their tab order (#266). This shows from the next update on: 0.2.5 kept no list of open documents, so 0.2.5 -> 0.2.6 still opens an empty window.
- Linux AppImage and Flatpak: under the Adwaita theme the window has a header bar with the toolbar and a menu button, rounded corners and a shadow; menus have shadows too. Under GNUstep's default theme the window manager's title bar is kept (#299, #300).

**Fixed since 0.2.5**
- Show in Folder after sharing a saved, unedited document selects the document in its own folder, not a temporary copy (#265). Any other share is a temporary copy, and the notice says so.
- Share opens one share panel at a time; choosing Share again brings it forward (libs-sharing cbc6726).
- Toolbar: in a narrow window Save goes into the overflow menu before Open (#280).
- The app icon has a transparent background instead of a white square (#281).
- Linux AppImage: the arrow keys, Home/End and Delete work in text again (#288, also in 0.2.5.1).
- Linux AppImage: on a computer with GNUstep installed, the app uses its own bundled services (pasteboard, notifications), not the host's (#302).
- Builds: packaged with gnustep-packager v0.1.4, which also updates the in-app updater.

**Known issues**
- Show in Folder still selects the temporary copy for a saved document whose extension is not lower-case `md` (`.markdown`, `.MD`, `.mdown`; `.TXT` in plain-text mode). Fix in 0.2.7.
- macOS with window restoration on: the restored documents come back in reversed tab order.
- Windows: typing in the source editor still costs about 46 ms of CPU per key (#164; the highlight timer moves to 0.2.7, the rest is upstream in libs-gui).
- Linux and Windows: shortcodes whose emoji is outside the BMP stay as typed (#267).

---

## Plan

**In**

| PR | What | State |
|---|---|---|
| #282, #283, #286, #287, #289 | Toolbar Save before Open, app icon alpha, task checkbox toggle, gnustep-packager v0.1.4, AppImage key bindings (#288) | merged |
| #295 | Read view: Reveal in Source for every block (#293) | merged 10071b1 |
| #296 | Design note: editing from the Read view (#63) | merged 8388dc3 |
| #297 | Reopen the open documents after an update (#266); macOS leaves AppKit-restored documents alone (e89aedf) | merged f7920d2; macOS 441/0 with OMD_WERROR=1, app and tests; Mac on-screen check at rc1 -> rc2 (Dan) |
| #299 | Linux AppImage: header bar and menu button by default, dock icon, own Library | merged 423987b |
| #300 | Linux packages carry the Adwaita theme's libs-back 0001-0005 and libs-gui 0002: shadows, rounded corners, the theme decides on its header bar (Dan go 2026-10-26) | merged 77eb9b6 |
| #301 | Vendor libs-sharing cbc6726: one share panel at a time | merged 7b44871 |
| #298 | #265 Show in Folder selects the document for a share of it as saved (Markdown Viewer Windows) | merged 315a2bc at 17c0c50; Linux review no blockers (Dan 2026-10-28: as it is) |
| #302 | Linux AppImage: a private TMPDIR, so the bundled gdnc and gpbs run instead of a host GNUstep's | merged eaeab3f (Dan 2026-10-28); replaces the dropped 0.2.5.2 |

**Out** (0.2.7, Dan 2026-10-28, unless Markdown Viewer Windows pushes them before rc1 packaging): the case-insensitive extension check for #265 (c921369), #164's highlight timer (highlight-timer-164, 019a95b). No 0.2.5.2: hotfix-0.2.5.2 stays as a branch, unreleased.

## Checklist

- [x] Scope (Dan, 2026-10-28): #298 as it is and #302 in; the extension fix and #164 to 0.2.7.
- [ ] Packaging runs green on the rc1 SHA (AppImage, Flatpak, MSI, dmg); record the Adwaita and WinUITheme commits the packages bundle.
- [ ] `v0.2.6-rc1` tagged on this notes PR's merge commit once packaging is green (Dan's go 2026-10-28); pre-release, outside the stable feeds.
- [ ] rc1 rounds on the CI packages, not dev builds:
  - Linux: AppImage and Flatpak, isolated (private display, private defaults). For each package:
    - Header bar window under Adwaita (#299, #300): the window has the theme's shadow and rounded corners, not a square, opaque rectangle. The header bar holds the toolbar and the menu button, and dragging, double-click to maximize and the window buttons work.
    - Menus and popovers under Adwaita draw their shadow (libs-back 0005).
    - GNUstep's default theme (GSTheme set to it, relaunch): the window manager's title bar, not GNUstep's NeXT title bar and not a header bar.
    - The AppImage no longer seeds GSX11HandlesWindowDecorations; a value the user set themselves still wins.
    - #266: open two documents, update 0.2.6-rc1 -> a newer build (rc2), and they reopen in tab order; from 0.2.5 the window stays empty (expected).
    - #302 (AppImage, on a host with GNUstep and its gdnc running): the bundled gdnc/gpbs start; Share to email, Show in Folder and dragging a file out work.
    - #293 Reveal in Source; #301 Share twice brings the open panel forward; #288 the arrows, Home/End and Delete work in text.
  - macOS: the dmg (on-screen #266/#297 at rc1 -> rc2).
  - Windows: the MSI; #265 Show in Folder. (#164's measurement moves with it to 0.2.7.)
- [ ] Dan: go for v0.2.6 final.

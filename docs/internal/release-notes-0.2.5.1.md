# Release notes: 0.2.5.1

A Linux-only hotfix for the AppImage (Dan, 2026-10-22: option A). It is
v0.2.5 (ba4f6ff) plus the fix for #288. Windows and macOS stay on 0.2.5,
which stays the Latest release.

---

**Fixed since 0.2.5**
- Linux AppImage: the arrow keys, Home/End, Page Up/Down and Delete work again in the editor and in every text field; they only beeped (#288). The AppImage left out GNUstep's key bindings; typing and Backspace were not affected, and neither was the Vim setting. 0.2.4 had the same fault. The Flatpak and the Windows and macOS packages were never affected.

**If you stay on 0.2.5**
- The same fix by hand: copy GNUstep's key bindings into your own Library, then quit and reopen Markdown Viewer:
  `mkdir -p ~/GNUstep/Library/KeyBindings && cp /usr/GNUstep/System/Library/KeyBindings/DefaultKeyBindings.dict ~/GNUstep/Library/KeyBindings/`
  (This needs a GNUstep installed on the system, which provides the file.)

---

## Plan

| Change | What | State |
|---|---|---|
| 12e133d | #288: stage `System/Library/KeyBindings`; require `DefaultKeyBindings.dict` when staging, in the AppImage and MSI `requiredPaths` and in `validate-appimage.sh` | cherry-picked from main's #289 |
| this branch | `windows-packaging.yml` and `macos.yml` skip the `v0.2.5.1` tag; the Linux release jobs mark it not Latest | Linux-only release |

**Why Linux only:** a four-part version (MSI 0.2.5.1) looks the same as 0.2.5 (MSI 0.2.5.0) to Windows Installer, which compares only the first three fields, so an MSI would not upgrade cleanly; and the bug is the AppImage's alone.

**Note:** AppImageUpdate follows the Latest release (the AppImage's zsync update information), so it keeps offering 0.2.5; the app's own updater reads the Linux stable feed, which moves to 0.2.5.1.

## Checklist

- [x] Reproduced and fixed under bwrap on a private display: the 0.2.5 AppImage with the key bindings added, Vim on then off and off from launch.
- [ ] Dan's go to push this branch's workflow and notes commits.
- [ ] `v0.2.5.1` tagged on this branch with Dan's go; then: the linux-appimage and linux-flatpak runs green, the Windows and macOS workflows not run, v0.2.5 still Latest, the Linux feed naming 0.2.5.1.
- [ ] An installed 0.2.5 AppImage offered 0.2.5.1 through the live feed (bwrap, private display), and the keys working in the updated app.

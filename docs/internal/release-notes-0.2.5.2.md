# Release notes: 0.2.5.2

A Linux-only update for the AppImage (Dan, 2026-10-24). It is v0.2.5.1
(473fa0f) plus the AppImage changes below. Windows and macOS stay on 0.2.5,
which stays the Latest release.

---

**Changed since 0.2.5.1**
- Linux AppImage and Flatpak: the window looks like a GNOME app's, with the header bar (the toolbar in the title bar), rounded corners and GNOME's window shadow; menus have rounded corners and a shadow too. The Adwaita theme turns this on by itself; under GNUstep's own theme the window keeps the desktop's title bar.
- Linux AppImage: the menus are behind the main menu button at the end of the header bar instead of in a menu bar, unless you have chosen otherwise: Preferences > Appearance > Menus still switches back to a menu bar.

**Fixed since 0.2.5.1**
- Linux AppImage: GNOME's dash and dash-to-dock show Markdown Viewer's icon for the running window instead of a generic one, also when the AppImage is installed with Gear Lever.
- Linux AppImage: a GNUstep theme installed in your own `~/GNUstep/Library/Themes` no longer replaces the Adwaita theme the AppImage carries. The AppImage now keeps its own Library in `~/GNUstep/Library/AppImage/org.objcmarkdown.MarkdownViewer`; your settings are unchanged.

---

## Plan

| Change | What | State |
|---|---|---|
| 96c4fe6 | packaged default `GnomeThemeMenuStyle = primary` (written only when unset; this commit also seeded `GSX11HandlesWindowDecorations = NO`, which 51e7e12 drops); `startupWMClass` in the manifest; the app wrapper's GNUstep.conf sets `GNUSTEP_USER_DIR_LIBRARY`; gnustep-packager v0.1.5 | cherry-picked from main's `appimage-desktop-integration` |
| gnustep-packager v0.1.5 | `StartupWMClass` in the AppImage desktop entry (defaults to the launch entry's name, `backends.appimage.startupWMClass` overrides) | branches `appimage-startup-wm-class` and `release-v0.1.5`; needs its PRs merged and the tag |
| 51e7e12, b2843f8 | the Adwaita theme's libs-back series (shadows, rounded corners, window types, alpha channel, popover shadows) and libs-gui patch (a theme turns GNUstep-drawn decorations on) carried in `packaging/patches`; the CI image rebuilt (`sha256:1494c94d...`) and pinned | cherry-picked from main's `appimage-csd-patches` (#300) |
| this branch | `windows-packaging.yml` and `macos.yml` skip `v0.2.5.2`; the Linux release jobs don't mark `v0.2.5.x` Latest | Linux-only release |

**Note:** a user whose own Library held the theme (a developer's machine) gets the bundled theme after the update; anything else they kept in `~/GNUstep/Library` (Services, fonts, an unsaved-document recovery snapshot from before the update) is no longer seen by the AppImage.

## Checklist

- [x] gnustep-packager: #71 green (its new tests pass) and merged; #72 merged; `v0.1.5` tagged and released.
- [x] main: `appimage-desktop-integration` PR (#299) green and merged.
- [ ] main: `appimage-csd-patches` (#300) green, the MSI build included (its libs-gui gets the new patch), and merged.
- [ ] The Flatpak builds with the new patches (the tag's linux-flatpak run is the first to build them).
- [ ] Dan's go to push this branch.
- [ ] `v0.2.5.2` tagged on this branch with Dan's go; then: the linux-appimage and linux-flatpak runs green, the Windows and macOS workflows not run, v0.2.5 still Latest, the Linux feed naming 0.2.5.2.
- [ ] By eye, on the released AppImage installed with Gear Lever, with no `GSX11HandlesWindowDecorations`, `GSBackHandlesWindowDecorations` or `GnomeThemeMenuStyle` in the global or MarkdownViewer domain: header bar, rounded corners and shadow, and the menu button on first launch; GNUstep's theme chosen in Preferences gives the desktop's title bar after a relaunch; the dock shows the app's icon; a theme in `~/GNUstep/Library/Themes` isn't loaded (`/proc/<pid>/maps` names the AppImage's `Adwaita.theme`). Record the bundled theme commit (`BundledThemes.txt`).
- [ ] An installed 0.2.5.1 AppImage offered 0.2.5.2 through the live feed.

# Release notes: 0.2.5.2

A Linux-only update for the AppImage (Dan, 2026-10-24). It is v0.2.5.1
(473fa0f) plus the AppImage changes below. Windows and macOS stay on 0.2.5,
which stays the Latest release.

---

**Changed since 0.2.5.1**
- Linux AppImage: the window has GNOME's header bar, with the toolbar in the title bar, and the menus are behind the main menu button at its end instead of in a menu bar. This applies only if you haven't chosen yourself: Preferences > Appearance > Menus still switches back to a menu bar.

**Fixed since 0.2.5.1**
- Linux AppImage: GNOME's dash and dash-to-dock show Markdown Viewer's icon for the running window instead of a generic one, also when the AppImage is installed with Gear Lever.
- Linux AppImage: a GNUstep theme installed in your own `~/GNUstep/Library/Themes` no longer replaces the Adwaita theme the AppImage carries. The AppImage now keeps its own Library in `~/GNUstep/Library/AppImage/org.objcmarkdown.MarkdownViewer`; your settings are unchanged.

---

## Plan

| Change | What | State |
|---|---|---|
| 96c4fe6 | packaged defaults `GSX11HandlesWindowDecorations = NO`, `GnomeThemeMenuStyle = primary` (written only when unset); `startupWMClass` in the manifest; the app wrapper's GNUstep.conf sets `GNUSTEP_USER_DIR_LIBRARY`; gnustep-packager v0.1.5 | cherry-picked from main's `appimage-desktop-integration` |
| gnustep-packager v0.1.5 | `StartupWMClass` in the AppImage desktop entry (defaults to the launch entry's name, `backends.appimage.startupWMClass` overrides) | branches `appimage-startup-wm-class` and `release-v0.1.5`; needs its PRs merged and the tag |
| this branch | `windows-packaging.yml` and `macos.yml` skip `v0.2.5.2`; the Linux release jobs don't mark `v0.2.5.x` Latest | Linux-only release |

**Note:** a user whose own Library held the theme (a developer's machine) gets the bundled theme after the update; anything else they kept in `~/GNUstep/Library` (Services, fonts, an unsaved-document recovery snapshot from before the update) is no longer seen by the AppImage.

## Checklist

- [ ] gnustep-packager: `appimage-startup-wm-class` PR green (its Pester tests weren't run locally: no PowerShell here) and merged; `release-v0.1.5` merged; `v0.1.5` tagged with Dan's go.
- [ ] main: `appimage-desktop-integration` PR green and merged.
- [ ] Dan's go to push this branch.
- [ ] `v0.2.5.2` tagged on this branch with Dan's go; then: the linux-appimage and linux-flatpak runs green, the Windows and macOS workflows not run, v0.2.5 still Latest, the Linux feed naming 0.2.5.2.
- [ ] By eye, on the released AppImage installed with Gear Lever, with no `GSX11HandlesWindowDecorations` or `GnomeThemeMenuStyle` in the global domain: header bar and menu button on first launch; the dock shows the app's icon; a theme in `~/GNUstep/Library/Themes` isn't loaded (`/proc/<pid>/maps` names the AppImage's `Adwaita.theme`). Record the bundled theme commit (`BundledThemes.txt`).
- [ ] An installed 0.2.5.1 AppImage offered 0.2.5.2 through the live feed.

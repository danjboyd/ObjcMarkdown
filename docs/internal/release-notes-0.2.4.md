# Release notes: 0.2.4

A fix release after 0.2.3. Linux leads it; ReleaseCoordinator coordinates.
Changes are counted from v0.2.3 (79e1c27).

---

**Fixed since 0.2.3**
- Code blocks are highlighted again in the packages. Highlighting no longer waits for tree-sitter to be installed; the highlighter never used it (#253).
- Linux: arrows and other symbols the text font lacks draw from a font that has them, not as "?" (#252).
- Share sheet:
  - Tiles stay where they are when you switch formats (#242).
  - Long titles fit on their tile.
  - Save a Copy opens in the document's folder, and keeps the file's type when you type a name without an extension (libs-sharing#24).
  - Windows: Open With shows the app chooser (libs-sharing#23).
- Linux packages:
  - Lists, quotes and code are spaced as in 0.2.2, not about 1.6x looser (#245).
  - LaTeX math shows as math, not as TeX text (#246).
  - Large documents render as fast as in 0.2.3 (#264; the #245 fix had slowed them).
- macOS:
  - Math via LaTeX finds MacTeX, Homebrew and MacPorts TeX when the app is opened from the Finder (#244).
  - The source editor keeps quotes and dashes as typed (#238).
  - Cancelling Print no longer says "Print failed" (#239).
- Windows: emphasis is italic, and the footnote back-link draws (#252).
- Windows: a window whose toolbar shares the menu bar's row no longer gets 32 px shorter at every launch. Switching tabs no longer moves a snapped window, and Save As asks before replacing a file. The MSI bundles WinUITheme 0.1.0-alpha10 (958c38f) (plugins-themes-winuitheme#155, #153, #166).

**Known issues**
- Windows: files can't be dragged out of the app yet (#213); use Copy File.
- Windows 11: pressing Esc in Open With's chooser closes the share sheet instead of bringing it back (libs-sharing#26).
- Linux: math drawn without ImageMagick has slightly thinner lines than a dev build's.
- Emoji shortcodes whose emoji is outside the BMP (`:rocket:`, `:tada:`) stay as typed on every platform. Windows: such emoji (🎉), and emoji typed in the editor, draw as "?" (#267).
- Windows: inline math draws faint in light mode, and math images are black-on-white boxes in dark mode.
- Windows: Show in Folder after a share selects the temporary copy (…\Temp\MarkdownViewer-share\…), not the document's folder (#265).
- Windows: after an update restarts the app, the window opens empty instead of reopening the document (#266).
- macOS: code blocks have tall line spacing.
- Carried over from 0.2.3: #164, #82, #177, #198, #197, and the Flatpak email and rclone notes.

---

## Plan

**In**

| PR | What | State |
|---|---|---|
| #248 | Share sheet audit fixes, libs-sharing 6f15162 | merged 5ac521a |
| #254 | #245 paragraph spacing on GNUstep | merged 1f597b8 |
| #255 | #246 built-in math SVG renderer | merged b1d6061 |
| #257 | vendor libs-sharing ff493df (#23, #24) | merged 7fce591 |
| #249 | macOS TeX paths (#244) | merged 53c0289 |
| #250 | macOS source editor quotes (#238) | merged 271902f; macOS hand check passed (macOS 26.5) |
| #251 | Print cancel isn't a failure (#239) | merged 2446a4c; macOS hand check passed (macOS 26.5) |
| #260 | WinUITheme alpha8 906e462 -> alpha10 958c38f | merged a5f47c3; MSI log shows 958c38f |
| #259 | gnustep-packager shared workflow 82090aa -> v0.1.1 | merged b27ad3c; packaging runs green |
| #262 | #252 Windows italics, footnote back-link; text fallback fonts | Windows-verified on alpha8; Linux fix c725c7e (emoji keep Symbola) |
| #263 | #253 highlighting without tree-sitter | Linux 33/33 |
| #264 | #254's spacing pass was quadratic; spacing left out where styles are made | Linux 33/33; back to pre-#254 speed |

**Out** (later): #243 (a caution symbol for the warnings), #241,
#213, #261 (macOS printed PDF named "Untitled"), libs-sharing#26, libs-sharing#11.

**Merge order for Dan.** Trial merges of 1 to 4 on b1d6061 have no
conflicts.
1. #257
2. #249
3. #250
4. #251
5. #260 (WinUITheme alpha10), after its CI MSI builds green
6. #259 (packager v0.1.1)
7. #263, #262, #264 (Dan, 2026-10-20: wait for them before rc1)


## Checklist

- [x] Dan's go (2026-10-20): merge the queue, then tag rc1; wait for #263, #262 and #264 first.
- [x] WinUITheme 0.1.0-alpha10 is published (958c38f, 2026-10-20); bump in #260.
- [x] `v0.2.4-rc1` tagged on 46b3635 with Dan's go (2026-10-20); 5 tag workflows green, 13 assets, pre-release.
- [x] rc1 rounds on the CI packages, not dev builds:
  - Linux: AppImage and Flatpak, isolated. Bundled Adwaita b2d4326. PASS (https://github.com/danjboyd/ObjcMarkdown/pull/258#issuecomment-6297980057).
  - macOS: the dmg. GO (build 314, 2026-10-20): codesign, appcast signature, rc kept off the stable appcast, Sparkle 0.2.3 -> rc1, #250, #251, #249 fallback, #263, Share, relaunch.
  - Windows: the MSI on Server 2022. GO (Markdown Viewer Windows, 2026-10-20; WinUITheme alpha10 958c38f): update 0.2.3 -> rc1, #262, #263, Share (#257), plugins-themes-winuitheme#166 and #155, 100/125/150%, vim, math, #264 shows no slowdown.
- [ ] Dan: go for v0.2.4 final, on the rc commit. Then the post-tag checks from the 0.2.3 checklist:
  - five green runs;
  - 13 assets, Latest;
  - three feed commits on gh-pages naming 0.2.4;
  - the same-SHA trap check;
  - the release body from these notes;
  - an installed 0.2.3 offered 0.2.4.

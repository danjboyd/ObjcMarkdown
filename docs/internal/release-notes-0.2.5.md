# Release notes: 0.2.5

A fix release after 0.2.4. Linux leads it; ReleaseCoordinator coordinates.
Changes are counted from v0.2.4 (649f34e).

---

**Fixed since 0.2.4**
- macOS: every GitHub emoji shortcode becomes its emoji, `:rocket:` and `:tada:` included (#267).
- A shortcode inside a bare URL stays as typed (`https://x.org/a:x:b` no longer shows an emoji in the address).
- Toolbar: when the window is too narrow, Explorer goes into the overflow menu first, then Share, then Open and Save; Read/Edit/Split stays. The Linux packages bundle Adwaita 0.1.0-alpha16 (928c2ca) and the MSI WinUITheme 0.1.0-alpha12 (cad2585), which both fill the overflow menu by each item's priority.
- macOS: printing and Save as PDF use the document's name without its extension (print.pdf), not "Untitled" (#261).
- Windows: Print and Export as PDF use the document's name too: the PDF's title and the print job are "print" for print.md (#277).
- Typing in the source editor redraws less: the line-number ruler and the Open Recent menu no longer force a full redraw on every key (#276), and on Windows the theme no longer redraws a focused view that has no focus ring (WinUITheme alpha12). On Windows that is about 5% less CPU per key; most of #164 remains (0.2.6 and upstream).
- Builds: packaged with gnustep-packager v0.1.3, on ubuntu-24.04 runners.

**Known issues**
- Linux and Windows: shortcodes whose emoji is outside the BMP (`:rocket:`, `:tada:`) stay as typed until GNUstep (libs-gui) can draw characters beyond the BMP (#267, kept open for the GNUstep side). Windows: such emoji (🎉), and emoji typed in the editor, draw as "?".
- Windows: Show in Folder after a share selects the temporary copy, not the document's folder (#265). Moves to 0.2.6.
- Windows: after an in-app update the app relaunches to an empty window instead of the documents that were open (#266, since 0.2.2). The old version's updater relaunches without arguments, so the 0.2.4 → 0.2.5 update does it too. Reopen the documents from Open Recent. Fix in 0.2.6.
- Windows: typing in the source editor still costs about 46 ms of CPU per key (#164; the highlight timer in 0.2.6, the rest upstream in libs-gui).
- Carried over from 0.2.4: #213, libs-sharing#26, the Linux math line weight without ImageMagick, Windows math contrast, macOS code-block line spacing, #82, #177, #198, #197, and the Flatpak email and rclone notes.

---

## Plan

**In**

| PR | What | State |
|---|---|---|
| #268 | gnustep-packager v0.1.1 -> v0.1.3 (00555f6); Linux jobs on ubuntu-24.04 | merged 80b3202; packaging green on #269 (AppImage 39655044367, Flatpak 39655048090, MSI 39655053166) |
| #269 (on #268) | Adwaita alpha15 -> alpha16 (928c2ca); WinUITheme alpha10 -> alpha11 (d0416a3); toolbar visibilityPriority (Dan: choice A) | merged 68f5027; Linux 34/34; Adwaita and GNUstep themes checked by eye; packages bundle 928c2ca (AppImage, Flatpak) and d0416a3 (MSI) |
| #270 | #267 macOS-only (Dan, 2026-10-21); Linux/Windows a known issue | merged 19aab61 (9e08a29, eabbdac: shortcodes stay as typed in link addresses); Linux 34/34, macOS 429/429 |
| #271 | UI checks keep the recovery snapshot in a private Library | merged 8ba422b |
| #273 | #261 print job title, macOS only (GNUstep's NSPrintOperation has no -setJobTitle:); OMDPrintJobTitle() shared for the Windows follow-up | e5dc085: drops a real extension from the job title and PDF title (Dan: "go with print.pdf"; the macOS 26.5 panel ignores NSPrintJobSavingURL); macOS 429/0; merged 5fb423d, which closed #261; the Windows follow-up is tracked separately (Markdown Viewer Windows sets it up with Dan) |
| #276 | #164 part A (Dan, 2026-10-21: "go with A on #164"): the ruler-thickness and Open Recent guards | merged 43a86da; removes 2840 menu-view and 232 scroll-view full invalidations per 200 keys; CPU within noise alone. #164 stays open |
| #277 | #261 on Windows: the HTML `<title>` and the print temp file carry the document's name | merged dbcad1c; checked in the rc1 MSI round |
| #278 | WinUITheme alpha11 -> alpha12 (cad2585, plugins-themes-winuitheme#173), the theme half of #164 part A | merged 5233152; with #276, Windows CPU per key 49.0 -> 46.6 ms (~5%), three interleaved rounds on Server 2022 (#164 comment) |

**Out** (0.2.6, Dan 2026-10-21; #266 again 2026-10-22): #265, #266; #164's highlight-timer re-style. Upstream: libs-gui NSTextView -_updateState redisplaying the whole view (#164).

**Check only:** #169 shipped in 0.2.3 (#226, 495c482). Verify it in the rc1 MSI round, then close it.

## Checklist

- [x] macOS: `make -C macos test OMD_WERROR=1` on eabbdac: 429 tests, 0 failures.
- [ ] Windows: WinUITheme toolbar overflow (now alpha12) checked in the MSI. Not named in the Windows rc1 report.
- [x] Dan's OK to push; #268-#272 opened 2026-10-21.
- [x] #273 (#261, macOS) merged.
- [x] #164 part A (#276, #278) and the Windows print-title follow-up (#277) merged before rc1.
- [x] Packaging runs green on 5233152 (AppImage 39682055192, Flatpak 39682058394, MSI 39682062025); Adwaita 928c2ca, WinUITheme cad2585.
- [x] `v0.2.5-rc1` tagged on 5233152 with Dan's go (2026-10-22); 5 tag workflows green, 13 assets, pre-release.
- [x] rc1 rounds on the CI packages, not dev builds:
  - Linux: AppImage and Flatpak, isolated. PASS (https://github.com/danjboyd/ObjcMarkdown/pull/275#issuecomment-6346829148).
  - macOS: the dmg. GO: Sparkle 0.2.4 -> rc1, smoke, #261, #267, #164.
  - Windows: the MSI. GO: updater 0.2.4 -> rc1, the MSI bundles WinUITheme cad2585, #164 about 5% less CPU, #277 titles, #169 verified and closed. The relaunch after the update opens an empty window (#266, 0.2.6).
- [x] Dan: go for v0.2.5 final (2026-10-22).
- [ ] v0.2.5 tagged on this notes PR's merge commit, then the post-tag checks:
  - five green runs;
  - 13 assets, Latest;
  - three feed commits on gh-pages naming 0.2.5;
  - the same-SHA trap check;
  - the release body from these notes;
  - an installed 0.2.4 offered 0.2.5.

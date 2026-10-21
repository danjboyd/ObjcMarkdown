# Release notes: 0.2.5

A fix release after 0.2.4. Linux leads it; ReleaseCoordinator coordinates.
Changes are counted from v0.2.4 (649f34e).

---

**Fixed since 0.2.4**
- macOS: every GitHub emoji shortcode becomes its emoji, `:rocket:` and `:tada:` included (#267).
- A shortcode inside a bare URL stays as typed (`https://x.org/a:x:b` no longer shows an emoji in the address).
- Toolbar: when the window is too narrow, Explorer goes into the overflow menu first, then Share, then Open and Save; Read/Edit/Split stays. The Linux packages bundle Adwaita 0.1.0-alpha16 (928c2ca) and the MSI WinUITheme 0.1.0-alpha11 (d0416a3), which both fill the overflow menu by each item's priority.
- macOS: printing and Save as PDF use the document's name without its extension (print.pdf), not "Untitled" (#261).
- Builds: packaged with gnustep-packager v0.1.3, on ubuntu-24.04 runners.

**Known issues**
- Linux and Windows: shortcodes whose emoji is outside the BMP (`:rocket:`, `:tada:`) stay as typed until GNUstep (libs-gui) can draw characters beyond the BMP (#267, kept open for the GNUstep side). Windows: such emoji (🎉), and emoji typed in the editor, draw as "?".
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
| #273 | #261 print job title, macOS only (GNUstep's NSPrintOperation has no -setJobTitle:); OMDPrintJobTitle() shared for the Windows follow-up | e5dc085: drops a real extension from the job title and PDF title (Dan: "go with print.pdf"; the macOS 26.5 panel ignores NSPrintJobSavingURL); macOS 429/0; open, CI running |

**In, not started:**
- #265: Windows reproduces it and finds the cause; Linux writes the fix if the cause is in shared code.
- #266: same split as #265.
- #164: Windows (Linux doesn't reproduce: 1.15 draws per key).

**Check only:** #169 shipped in 0.2.3 (#226, 495c482). Verify it in the rc1 MSI round, then close it.

## Checklist

- [x] macOS: `make -C macos test OMD_WERROR=1` on eabbdac: 429 tests, 0 failures.
- [ ] Windows: WinUITheme alpha11 toolbar overflow checked in the MSI.
- [x] Dan's OK to push; #268-#272 opened 2026-10-21.
- [ ] #265, #266 and #164 merged, or each dropped by Dan, before rc1; #273 (#261) merged.
- [ ] Packaging runs green on the merged result (AppImage, Flatpak, MSI, dmg); bundled theme commits recorded.
- [ ] `v0.2.5-rc1` with Dan's go, then rc rounds on the CI packages.
- [ ] Windows MSI round on the lease: the installed MSI, the updater from 0.2.4 to rc1, and #169: Export as PDF, Print and Share as PDF (then close #169).

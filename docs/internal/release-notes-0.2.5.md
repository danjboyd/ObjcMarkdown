# Release notes: 0.2.5

A fix release after 0.2.4. Linux leads it; ReleaseCoordinator coordinates.
Changes are counted from v0.2.4 (649f34e).

---

**Fixed since 0.2.4**
- macOS: every GitHub emoji shortcode becomes its emoji, `:rocket:` and `:tada:` included (#267).
- Toolbar: when the window is too narrow, Explorer goes into the overflow menu first, then Share, then Open and Save; Read/Edit/Split stays. The Linux packages bundle Adwaita 0.1.0-alpha16 (928c2ca) and the MSI WinUITheme 0.1.0-alpha11 (d0416a3), which both fill the overflow menu by each item's priority.
- Builds: packaged with gnustep-packager v0.1.3, on ubuntu-24.04 runners.

**Known issues**
- Linux and Windows: shortcodes whose emoji is outside the BMP (`:rocket:`, `:tada:`) stay as typed until GNUstep (libs-gui) can draw characters beyond the BMP (#267, kept open for the GNUstep side). Windows: such emoji (🎉), and emoji typed in the editor, draw as "?".
- Carried over from 0.2.4: #213, libs-sharing#26, the Linux math line weight without ImageMagick, Windows math contrast, macOS code-block line spacing, #82, #177, #198, #197, and the Flatpak email and rclone notes.

---

## Plan

**In**

| PR | What | State |
|---|---|---|
| #268 | gnustep-packager v0.1.1 -> v0.1.3 (00555f6); Linux jobs on ubuntu-24.04 | b011663, 6662de6; packaging runs dispatched on #269 (39655044367 AppImage, 39655048090 Flatpak, 39655053166 MSI) |
| #269 (on #268) | Adwaita alpha15 -> alpha16 (928c2ca); WinUITheme alpha10 -> alpha11 (d0416a3); toolbar visibilityPriority (Dan: choice A) | d368353, 34d2767, e409afb on ci-pins; Linux 34/34; Adwaita and GNUstep themes checked by eye |
| #270 | #267 macOS-only (Dan, 2026-10-21); Linux/Windows a known issue | 9e08a29; Linux 34/34; macOS test pending |
| #271 | UI checks keep the recovery snapshot in a private Library | ae132a9; Linux 34/34 |

**In, not started:**
- #265: Windows reproduces it and finds the cause; Linux writes the fix if the cause is in shared code.
- #266: same split as #265.
- #164: Windows (Linux doesn't reproduce: 1.15 draws per key).
- #261: macOS.

**Check only:** #169 shipped in 0.2.3 (#226, 495c482). Verify it in the rc1 MSI round, then close it.

## Checklist

- [ ] macOS: `make -C macos test OMD_WERROR=1` on 9e08a29.
- [ ] Windows: WinUITheme alpha11 toolbar overflow checked in the MSI.
- [x] Dan's OK to push; #268-#272 opened 2026-10-21.
- [ ] #265, #266, #164 and #261 merged, or each dropped by Dan, before rc1.
- [ ] Packaging runs green on the merged result (AppImage, Flatpak, MSI, dmg); bundled theme commits recorded.
- [ ] `v0.2.5-rc1` with Dan's go, then rc rounds on the CI packages.
- [ ] Windows MSI round on the lease: the installed MSI, the updater from 0.2.4 to rc1, and #169: Export as PDF, Print and Share as PDF (then close #169).

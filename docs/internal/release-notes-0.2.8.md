# Release notes: 0.2.8

Draft, 2026-11-12 (objcmarkdown-lead). Changes are counted from v0.2.7.
A bug-fix release, the last before MarkdownViewer goes into maintenance
mode (Dan, ask #7016).

---

**New since 0.2.7**
- None. The performance work (#346), Edit Block (#294) and the macOS Quick
  Look preview are parked as drafts for maintenance mode.

**Fixed since 0.2.7**
- Linux: a click on the file icon in the Share sheet or the Share notice no
  longer starts a drag; a drag starts only after the pointer moves a few
  points with the button held. A partial drag from the Share sheet had left a
  Linux desktop unable to take clicks (#395, #397).
- Windows: Print, Export as PDF and Share as PDF typeset math with the
  bundled TeX, as the preview does (#364, #377).
- Windows: printed and exported PDFs no longer show Edge's header and footer
  (date, title, temporary file path), on older Edge versions too (#378, #383).
- Share: the copy of a saved Markdown file keeps its own extension, as
  written (`long.markdown`, `UPPER.MD`), not always `.md` (#372, #387).
- Windows: the Share notice shows the document's page icon instead of
  GNUstep's `?`, tinted to stay visible in dark mode (#388, #389).

**Known issues** (carried over from 0.2.7 unless fixed above)
- GNUstep: a file drag that has really started can't be cancelled with
  Escape; it ends only when the mouse button is released. That's in
  GNUstep's drag code; #395 has the details. 0.2.8 only stops a click from
  starting one.
- Linux: no Flatpak for 0.2.8; the Flatpak build fails in CI before our
  code builds (#398). Flatpak users stay on 0.2.7 until the next release.
- Linux: the 0.2.8 AppImage was checked to launch, but the Share click fix
  (#395) was tested only by unit tests and CI, not on the installed package.
- GNUstep: dragging the Share notice's file shows GNUstep's `?` as the drag
  image (#391).
- Windows at 150%: a short black bar at the bottom left of the source pane
  can cut off the last line (#325).
- Windows: typing in the source editor costs about 70 ms of CPU per key on a
  large document (#164).
- Linux: Split view can still stall on large documents (#318).
- Linux AppImage: opening a second file starts a second copy of the app
  (#309); More... > View Changes in the update prompt opens nothing (#369).
- Linux and Windows: the app still writes six keys into NSGlobalDomain
  (#335; the fix, #341, is parked).
- Linux and Windows: shortcodes whose emoji is outside the BMP stay as typed
  (#267).

---

## Plan

- [x] Scope (Dan, ask #7016): #395 plus #377, #383, #387, #389.
- [x] Merged (Dan, ask #7062): #377, #383, #387 (main merged in, both tests
  kept), #389, #397. Main f50408c, CI green on all three platforms.
- [x] `v0.2.8-rc1` tagged on f50408c (Dan, ask #7073): five tag workflows
  green, pre-release, 13 assets. AppImage sha256 `4b1aeb1f...9ebe`
  (Adwaita d274272, 0.1.0-alpha22); MSI sha256 `3cbdc5c0...3fe2`.
- [x] Windows: installed MSI check (Dan, ask #7546; markdown-viewer-windows,
  2026-11-16). No 7097 lease was ever made. Lease
  lease-20261116174511-zelh8b (windows-2022), destroyed and verified. MSI
  from tag run 43281170812, sha256 `3cbdc5c0...3fe2` matched on host and VM;
  WinUITheme 72f2a10 (same as 0.2.7); Edge 86. PASS: #377 (math in Export,
  Print and Share PDF), #383 (no Edge header or footer), #387 (`long.markdown`,
  `UPPER.MD`), #389 (icon contrast 15.05:1 dark, 16.30:1 light).
- [x] Linux: installed AppImage check (markdown-viewer-linux). Ask #7098
  stopped at the first gate (no xdotool in the VM); the retry, ask #7114
  (xdotool from Debian's mirror), stopped when the private Xwayland didn't
  answer within 3 s. The app never launched; both leases destroyed and
  verified. Evidence: /home/danboyd/.cache/omd-agent/rc1-7098-1966 on the
  Linux host. 2026-11-16, ask #7545: Dan chose to fix the harness's
  Xwayland wait (local only, no push), then one lease. It stopped before
  any lease: the harness lived in /tmp and was lost in a reboot. Ask #7550:
  Dan approved rebuilding it as a local commit under tools/dev/ (push is a
  separate ask), then one lease. Done as local commit 7d24214 (not
  pushed). The lease (lease-20261116172444-bbb742, Debian 13) passed the
  Xwayland wait (1.6 s); the installed AppImage launched and showed its
  window. A probe was read too early and the next step ran anyway (agent
  error); the lease was destroyed at once and verified gone on iep-vm2 and
  iep-ocr01. The Share click test did NOT run. Ask #7584 (2026-11-16): Dan
  chose to ship with that gap noted.
- [x] macOS: the rc1 dmg launches (Dan, ask #7555; markdown-viewer-macos,
  2026-11-16 11:22-11:32 CT). macOS 26.5.1; dmg sha256 `604a00d9...994f`
  matches GitHub; signed app 0.2.8 build 553 run from a scratch copy. A test
  file rendered (heading, list, bold, link, code block); no Gatekeeper or
  signing prompt; quit from its own menu; its preferences restored byte for
  byte. Nothing installed.
- [x] Dan: final from rc1 (ask #7628). `v0.2.8` (annotated) pushed on
  f50408c 2026-11-16. GitHub Latest, not a pre-release. Linux and Windows
  stable feeds and the macOS appcast list 0.2.8. AppImage, MSI, macOS and
  CI image workflows green; 12 of 13 assets.
- [x] Flatpak: linux-flatpak run 43927663329 failed three times ("Invalid
  cross-device link" updating the container's preinstalled SDK). Re-run
  once; then the only cache entry deleted and re-run once (Dan, ask #7650);
  same failure. Dan, ask #7655: ship without a Flatpak; issue #398.

Paused 2026-11-12 ~13:25 CT by Dan's capacity pause (manager #6935);
lifted 2026-11-16 (Dan, #7513, "light").

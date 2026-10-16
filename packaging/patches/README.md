# GNUstep patches the Linux and Windows packages carry

Fixes to GNUstep that the app's Linux and Windows builds apply until they
are fixed upstream:

- the Flatpak (`packaging/flatpak/io.github.danjboyd.MarkdownViewer.yml`,
  as `patch` sources of the gnustep-base, gnustep-gui and gnustep-back
  modules);
- the CI image (`ci/linux/Dockerfile`), which also builds the AppImage;
  `ci-image.yml` passes this directory as the `patches` build context.
  After a change here the image is rebuilt, and both workflows that pin
  its digest (`linux-gnustep-clang.yml`, `linux-appimage.yml`) need the
  new one.
- the Windows MSI: `packaging/scripts/build-windows-gnustep-patches.sh`
  (run by `build-windows.ps1`) rebuilds gnustep-base 1.31.1 and
  gnustep-gui 0.32.0 from their release tarballs the way MSYS2's CLANG64
  packages are built, with these patches, and replaces the toolchain's
  two DLLs before the app is built and staged. It checks that the
  toolchain has those versions, and replaces the DLLs only in CI.
  `packaging/windows/patches/` holds upstream commits the 0.31.1 and
  0.32.0 releases lack and the Linux pins already include: the one
  MSYS2's gnustep-base package applies (bace6f54), and libs-gui
  3f5efad1b, which stops `NSScrollView` re-tiling without end when
  `autohidesScrollers` shows one scroller and hides the other (a large
  document in Split, #121). Drop each when the toolchain's release has it.

Each patch applies to the commit the Linux builds pin and to the release
the Windows build uses; check both before moving either. The macOS build
uses Cocoa and doesn't need them.

| Patch | Fixes | Upstream |
|---|---|---|
| `libs-base/0001-GSAttributedString-hash-...` | Attribute dictionaries cached by count: building text with many distinct attributes is quadratic (#94) | not sent |
| `libs-gui/0001-GSLayoutManager-compile-out-...` | `-_sanityChecks` walks every glyph run on each glyph generation: layout is quadratic (#94) | reported as gnustep/libs-gui#992 (issue); patch not sent |
| `libs-back/0001-x11-list-WM_DELETE_WINDOW-...` | Windows the theme decorates don't list `WM_DELETE_WINDOW`, so Alt+F4 or a close from the Overview or dock makes Mutter kill the app, unsaved edits and all. Linux only (the MSI uses the win32 backend). Backport to 0.32 of danjboyd/libs-back `x11-wm-delete-window` (1ecd259), as LinDirStat carries it | not sent |
| `libs-back/0002-x11-answer-TARGETS-and-text-uri-list-...` | A file dragged out of the app (the Share dialog, #175) was refused by every drop target: the backend answered neither `TARGETS` nor `text/uri-list`, nor refused other types. Linux only | prepared for upstream (`docs/upstream-patches/libs-back/0001-...`, danjboyd/libs-back-xdnd `5bcfb0b`); carried first, to live with it, before sending |
| `libs-back/0003-x11-speak-XDND-version-3-and-send-...` | Drags announced XDND version 2, which GTK ignores, and the version check was inverted, so no time stamp (and at version 3 no action) was sent. With 0002, files drop on Nautilus. Linux only | prepared for upstream (`docs/upstream-patches/libs-back/0002-...`, `7be8987`); carried first |

These are our own fixes, carried here. Sending them to GNUstep is separate
and follows [docs/UPSTREAM_POLICY.md](../../docs/UPSTREAM_POLICY.md): they
would need GNUstep regression tests, ChangeLog entries and Dan's sign-off
first.

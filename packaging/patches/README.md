# GNUstep patches the Linux and Windows packages carry

Fixes to GNUstep that the app's Linux and Windows builds apply until they
are fixed upstream:

- the Flatpak (`packaging/flatpak/io.github.danjboyd.MarkdownViewer.yml`,
  as `patch` sources of the gnustep-base and gnustep-gui modules);
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
  `packaging/windows/patches/` holds the upstream commit MSYS2's
  gnustep-base package applies, which the Linux pins already include.

Each patch applies to the commit the Linux builds pin and to the release
the Windows build uses; check both before moving either. The macOS build
uses Cocoa and doesn't need them.

| Patch | Fixes | Upstream |
|---|---|---|
| `libs-base/0001-GSAttributedString-hash-...` | Attribute dictionaries cached by count: building text with many distinct attributes is quadratic (#94) | not sent |
| `libs-gui/0001-GSLayoutManager-compile-out-...` | `-_sanityChecks` walks every glyph run on each glyph generation: layout is quadratic (#94) | reported as gnustep/libs-gui#992 (issue); patch not sent |

These are our own fixes, carried here. Sending them to GNUstep is separate
and follows [docs/UPSTREAM_POLICY.md](../../docs/UPSTREAM_POLICY.md): they
would need GNUstep regression tests, ChangeLog entries and Dan's sign-off
first.

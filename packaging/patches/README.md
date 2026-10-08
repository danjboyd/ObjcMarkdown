# GNUstep patches the Linux packages carry

Fixes to GNUstep that the app's Linux builds apply to the pinned upstream
commits until they are fixed upstream:

- the Flatpak (`packaging/flatpak/io.github.danjboyd.MarkdownViewer.yml`,
  as `patch` sources of the gnustep-base and gnustep-gui modules);
- the CI image (`ci/linux/Dockerfile`), which also builds the AppImage;
  `ci-image.yml` passes this directory as the `patches` build context.
  After a change here the image is rebuilt, and both workflows that pin
  its digest (`linux-gnustep-clang.yml`, `linux-appimage.yml`) need the
  new one.

Each patch applies to the commit the builds pin; check that before moving
a pin. The Windows and macOS builds don't carry them.

| Patch | Fixes | Upstream |
|---|---|---|
| `libs-base/0001-GSAttributedString-hash-...` | Attribute dictionaries cached by count: building text with many distinct attributes is quadratic (#94) | not sent |
| `libs-gui/0001-GSLayoutManager-compile-out-...` | `-_sanityChecks` walks every glyph run on each glyph generation: layout is quadratic (#94) | not sent |

These are our own fixes, carried here. Sending them to GNUstep is separate
and follows [docs/UPSTREAM_POLICY.md](../../docs/UPSTREAM_POLICY.md): they
would need GNUstep regression tests, ChangeLog entries and Dan's sign-off
first.

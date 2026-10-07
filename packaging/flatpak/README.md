# Flatpak

`io.github.danjboyd.MarkdownViewer.yml` builds MarkdownViewer as a Flatpak on
the freedesktop 25.08 runtime, with everything it needs inside:

- the GNUstep stack (tools-make, libobjc2, libdispatch, libs-base, libs-gui,
  libs-back with cairo), built with clang from the SDK's LLVM extension at the
  commits the CI image pins in `ci/linux/Dockerfile`;
- the Adwaita GNUstep theme, at the commit `packaging/inputs.json` pins;
- the app and its libraries, from this checkout.

GNUstep uses its FHS layout under `/app`. The `markdownviewer` launcher makes
Adwaita the theme until the user picks another in Preferences.

When the pins in `ci/linux/Dockerfile` or `packaging/inputs.json` change,
change them here too.

## Building

[linux-flatpak.yml](../../.github/workflows/linux-flatpak.yml) builds the bundle
in the official Flatpak builder container: by hand (workflow_dispatch, the
bundle is an artifact of the run) or on a `v*` tag (the bundle is attached to the
release).

Locally, with `flatpak-builder` (or `org.flatpak.Builder`) and the freedesktop
25.08 SDK and its `llvm20` extension installed:

```sh
flatpak-builder --user --install --force-clean build-dir \
  packaging/flatpak/io.github.danjboyd.MarkdownViewer.yml
flatpak run io.github.danjboyd.MarkdownViewer
```

To install a bundle from a release or a workflow run:

```sh
flatpak install --user MarkdownViewer.flatpak
```

## Not included

`pandoc` (import and export of DOCX, ODT, RTF and HTML) and a TeX toolchain
(math typeset through LaTeX) aren't bundled. Without them those formats are
disabled and math is drawn as styled text.

## Permissions

X11 (GNUstep's backend; XWayland under Wayland), the network (Open Location
and remote images) and the home folder (the explorer browses folders and
repositories). Open and save use the theme's portal file chooser.

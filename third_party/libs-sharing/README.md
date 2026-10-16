# libs-sharing

Apple's sharing API for GNUstep: `NSSharingService`,
`NSSharingServicePicker` and `NSSharingServicePickerToolbarItem`, with a
share sheet the theme draws and services that talk to the desktop.

libs-gui declares these classes with no methods. This library installs
the methods into libs-gui's classes when it loads (`GSSharingInstall()`),
the way danjboyd/gnustep-window-tabbing adds tabbing to `NSWindow`, so code
written for macOS works unchanged and the code can move into libs-gui
later.

## What an app gets

```objc
#import "GSSharing.h"

NSSharingServicePicker *picker = [[NSSharingServicePicker alloc]
                                    initWithItems: items];  // NSURL, NSString, NSAttributedString, NSImage
[picker setDelegate: self];
[picker showRelativeToRect: [button bounds] ofView: button preferredEdge: NSMinYEdge];
```

- **The share sheet** (`GSSharingPickerPanel`): a preview of the items (an
  icon that drags a file out, the name, the size), an optional accessory
  view under it (`-setAccessoryView:`, a GNUstep extension, for a format
  switcher), and the services as buttons with their images. Standard
  controls only. `-setItems:` while it shows updates it.
- **Built-in services:** Email (Linux: the email portal in a Flatpak, else
  `xdg-email --attach` for mail apps that take attachments, through the
  document portal for a Flatpak mail app, else a `mailto:` draft and a
  notice offering the file; text goes on the clipboard to paste as the
  body), Copy (files as `text/uri-list`, text as RTF and plain text, images
  as TIFF), Save a Copy, Show in Folder (FileManager1, or the OpenURI portal
  in a Flatpak).
- **The app's own services:** `-initWithTitle:image:alternateImage:handler:`
  (blocks) or `-initWithTitle:image:alternateImage:target:action:` (GCC),
  added through the delegate's
  `-sharingServicePicker:sharingServicesForItems:proposedSharingServices:`.
- **Plug-ins:** bundles with the extension `.sharingservice` in any
  `Library/SharingServices`, whose principal class conforms to
  `GSSharingServiceProvider`; or `GSSharingRegisterProvider()`.

## Using it

As a library: `make`, link `-lGSSharing`. Or compiled into the app (as
Markdown Viewer does), so the package needs nothing new; see
`GSSharing.make`. On Linux and the BSDs the code uses GIO
(`gio-unix-2.0`) when pkg-config finds it.

## Building and testing

```sh
make                # the library
make check-model    # Tests/gui: no display needed
make sharedemo      # Examples/ShareDemo
```

## Status

Linux works today (Adwaita and GNUstep's own theme). The Windows backend
(the system share UI and MAPI) is the next part. Upstream: nothing goes to
GNUstep without Dan's sign-off, following the upstream policy in
danjboyd/ObjcMarkdown (`docs/UPSTREAM_POLICY.md`).

LGPL-2.1-or-later (`LICENSE`).

AI assistance: this code, its tests and its documentation were written
with Claude (Anthropic's Claude Code).

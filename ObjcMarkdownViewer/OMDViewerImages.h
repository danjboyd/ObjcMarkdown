// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

// Images from the app bundle, prepared and tinted for toolbar buttons, and
// the copy button glyphs.
NSImage *OMDImageNamed(NSString *resourceName);
void OMDSetToolbarItemImage(NSToolbarItem *item, NSImage *image);
NSImage *OMDToolbarImageNamed(NSString *resourceName);
NSImage *OMDToolbarTintedImage(NSImage *image, NSColor *tint);
NSImage *OMDToolbarThemedImageNamed(NSString *resourceName);
NSImage *OMDCodeBlockCopyImage(void);
NSImage *OMDCodeBlockCopiedCheckImage(void);

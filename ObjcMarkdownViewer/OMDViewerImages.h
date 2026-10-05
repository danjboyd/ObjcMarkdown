// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

// Images from the app bundle.
NSImage *OMDImageNamed(NSString *resourceName);
// One of the app's symbolic icons (Resources/icons, made by
// tools/icons/make-symbolic-icons.py), by its name without ".png", such as
// @"omd-document-open-symbolic". The image keeps that name, so a theme
// that tints template images draws it in the colour of the text around it.
NSImage *OMDSymbolicImageNamed(NSString *name);
// Windows toolbar only (waits with the Windows work): a toolbar-sized copy
// of image in tint.
NSImage *OMDToolbarTintedImage(NSImage *image, NSColor *tint);

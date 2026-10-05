// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

// A 16-point symbolic icon for a formatting command (an
// OMDFormattingCommandTag), drawn in one colour in the style of Adwaita's
// symbolic icons. Returns nil for an unknown tag.
NSImage *OMDFormattingBarIcon(NSInteger commandTag, NSColor *color);

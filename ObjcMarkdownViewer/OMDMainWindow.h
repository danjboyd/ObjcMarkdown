// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

// Routes Close through the delegate's windowShouldClose: like the close button,
// and takes Command-+ as Zoom In beside the menu's Command-=.
@interface OMDMainWindow : NSWindow
@end

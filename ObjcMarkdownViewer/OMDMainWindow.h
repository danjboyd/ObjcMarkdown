// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

// A delegate that keeps several documents as tabs in one window.
@protocol OMDMainWindowTabClosing
// Closes the selected tab when the window has other tabs (asking about
// unsaved changes first) and returns YES; returns NO when it is the only
// tab, so the window closes instead.
- (BOOL)closeSelectedDocumentTabIfOthersRemain;
@end

// Routes Close through the delegate's windowShouldClose: like the close button,
// and takes Command-+ as Zoom In beside the menu's Command-=. On GNUstep,
// File > Close closes the selected document tab while others remain.
@interface OMDMainWindow : NSWindow
@end

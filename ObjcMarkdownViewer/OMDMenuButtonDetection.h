// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

#if defined(GNUSTEP)
// Whether a window's frame view (the superview of its content view) shows
// the menus behind a button rather than as a bar of titles, judged from what
// is laid out: a horizontal menu view with no height (the button is elsewhere
// in the window, such as a header bar), or one holding a subview (a menu view
// draws its titles itself, so a subview is a control standing in for them).
// NO when there is no horizontal menu view at all.
BOOL OMDFrameViewShowsMenuButton(NSView *frameView);

// The same for the app's windows: the first one with a horizontal menu view
// decides. NO when no window has one.
BOOL OMDAppShowsMenuButton(void);
#endif

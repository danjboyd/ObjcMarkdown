// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

@class OMDWindowController;

// The application's delegate. It makes the first window's controller and
// passes the application's events (launch, files to open, activation) to
// it; each window, the first and any New Window, has its own controller.
@interface OMDAppDelegate : NSObject <NSApplicationDelegate>
{
    OMDWindowController *_mainWindowController;
}

@end

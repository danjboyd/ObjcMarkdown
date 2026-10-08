// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

@class OMDWindowController;
@class OMDPreferencesController;

// The application's delegate. It makes the first window's controller and
// passes the application's events (launch, files to open, activation) to
// it; each window, the first and any New Window, has its own controller.
//
// The main menu's commands come here and go on to the window in front, so
// Save, Print or Open act on the window you are looking at. Settings is one
// window for the app: what it changes applies to every window.
@interface OMDAppDelegate : NSObject <NSApplicationDelegate>
{
    OMDWindowController *_mainWindowController;
    OMDPreferencesController *_preferencesController;
    id _updaterController;
    NSMutableSet *_windowActionNames;
}

// The Settings window's controller, shared by every window.
- (OMDPreferencesController *)preferencesController;

// The controller of the window in front (the key window, else the main
// window, else the front-most visible one), or the first window's.
- (OMDWindowController *)activeWindowController;

// Sends the commands of menu's items that target the app delegate on to
// the window in front.
- (void)routeWindowActionsOfMenu:(NSMenu *)menu;

- (void)checkForUpdates:(id)sender;

@end

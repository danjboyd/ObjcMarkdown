// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

// What the toolbar shows and does for the window that hosts it.
@protocol OMDToolbarControllerDelegate <NSObject>
- (BOOL)hasLoadedDocument;
- (BOOL)canSaveCurrentDocument;
- (BOOL)isExplorerSidebarVisible;
- (void)updateModeControlSelection;
- (void)toggleExplorerSidebar:(id)sender;
- (void)openDocument:(id)sender;
// A new menu of the recent documents, each item opening its file.
- (NSMenu *)recentDocumentsMenu;
- (void)saveDocument:(id)sender;
@end

// The window's toolbar, the same on every platform: the explorer, open and
// save buttons, a flexible space and the Read/Edit/Split switcher. The
// theme presents it (the Adwaita theme puts it in the header bar,
// GnomeThemeHeaderBarToolbar; WinUITheme draws a CommandBar). Export,
// Print and Preferences are in the menus; zoom and status are in the
// status bar. The controls' actions go to the delegate, which also
// validates the toolbar items.
@interface OMDToolbarController : NSObject <NSToolbarDelegate>
{
    id<OMDToolbarControllerDelegate> _delegate;
    NSToolbar *_toolbar;
    NSView *_modeContainer;
    NSSegmentedControl *_modeControl;
}

// The delegate is not retained.
- (instancetype)initWithDelegate:(id<OMDToolbarControllerDelegate>)delegate;

- (void)installInWindow:(NSWindow *)window;
// Validates the toolbar items again (Save's enabled state, for one).
- (void)updateToolbarActionControlsState;

// The Read/Edit/Split switcher, nil until the toolbar builds it.
- (NSSegmentedControl *)modeControl;

@end

// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

// Builds the app's main menu bar (the Windows layout on Windows). Every
// item's action goes to the target, which also validates the items and
// fills the Open Recent submenu as its delegate.
@interface OMDMainMenu : NSObject
{
    NSMenu *_menubar;
    NSMenu *_openRecentMenu;
}

// The target is not retained.
- (instancetype)initWithTarget:(id)target;

- (NSMenu *)menubar;
- (NSMenu *)openRecentMenu;

@end

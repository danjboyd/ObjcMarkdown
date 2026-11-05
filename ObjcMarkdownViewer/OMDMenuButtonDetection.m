// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import "OMDMenuButtonDetection.h"

#if defined(GNUSTEP)
static NSMenuView *OMDHorizontalMenuViewInFrameView(NSView *frameView)
{
    for (NSView *subview in [frameView subviews]) {
        if ([subview isKindOfClass:[NSMenuView class]] && [(NSMenuView *)subview isHorizontal]) {
            return (NSMenuView *)subview;
        }
    }
    return nil;
}

BOOL OMDFrameViewShowsMenuButton(NSView *frameView)
{
    NSMenuView *menuView = OMDHorizontalMenuViewInFrameView(frameView);
    if (menuView == nil) {
        return NO;
    }
    return NSHeight([menuView frame]) <= 0.0 || [[menuView subviews] count] > 0;
}

BOOL OMDAppShowsMenuButton(void)
{
    for (NSWindow *window in [NSApp windows]) {
        NSView *frameView = [[window contentView] superview];
        if ([window menu] != nil && OMDHorizontalMenuViewInFrameView(frameView) != nil) {
            return OMDFrameViewShowsMenuButton(frameView);
        }
    }
    return NO;
}
#endif

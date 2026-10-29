// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

static const CGFloat OMDWin11SplitDividerThickness = 1.0;
static const CGFloat OMDWin11SplitDividerHitThickness = 12.0;

@interface OMDWin11SplitView : NSSplitView
{
    BOOL _omdTrackingDivider;
}
- (void)omdInvalidateCursorRects;
- (void)omdSnapSubviewsToPixels;
// Whether the user is dragging a divider: the subviews' resizes then are
// the user's choice, not a layout's.
- (BOOL)omdIsTrackingDivider;
@end

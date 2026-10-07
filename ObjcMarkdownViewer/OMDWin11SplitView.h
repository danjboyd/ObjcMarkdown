// ObjcMarkdownViewer
// SPDX-License-Identifier: GPL-2.0-or-later

#import <AppKit/AppKit.h>

static const CGFloat OMDWin11SplitDividerThickness = 3.0;
static const CGFloat OMDWin11SplitDividerHitThickness = 12.0;

@interface OMDWin11SplitView : NSSplitView
{
    NSMutableArray *_dividerTrackingTags;
    NSInteger _hoveredDividerIndex;
    NSInteger _activeDividerIndex;
}
- (void)omdRebuildDividerTrackingRects;
- (void)omdSnapSubviewsToPixels;
@end
